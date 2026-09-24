import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import { execSync } from 'node:child_process';

function getFiles(dir) {
  let results = [];
  const list = fs.readdirSync(dir);
  for (const file of list) {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(getFiles(fullPath));
    } else if (file.endsWith('.ts') || file.endsWith('.tsx') || file.endsWith('.js') || file.endsWith('.jsx')) {
      results.push(fullPath);
    }
  }
  return results;
}

const srcFiles = getFiles('src');
const rpcCalls = [];

function extractKeysFromNode(expr, sourceFile) {
  if (!expr) return [];
  while (ts.isAsExpression(expr) || ts.isTypeAssertionExpression(expr) || ts.isParenthesizedExpression(expr) || ts.isNonNullExpression(expr)) {
    expr = expr.expression;
  }
  if (ts.isObjectLiteralExpression(expr)) {
    const keys = [];
    for (const prop of expr.properties) {
      if (ts.isPropertyAssignment(prop) || ts.isShorthandPropertyAssignment(prop)) {
        keys.push(prop.name.getText(sourceFile));
      } else if (ts.isSpreadAssignment(prop)) {
        keys.push(...extractKeysFromNode(prop.expression, sourceFile));
      }
    }
    return keys;
  }
  if (ts.isIdentifier(expr)) {
    const varName = expr.text;
    let foundKeys = [];
    function findDecl(n) {
      if (ts.isVariableDeclaration(n) && n.name.getText(sourceFile) === varName && n.initializer) {
        foundKeys = extractKeysFromNode(n.initializer, sourceFile);
      }
      ts.forEachChild(n, findDecl);
    }
    findDecl(sourceFile);
    return foundKeys;
  }
  if (ts.isCallExpression(expr)) {
    const fnName = expr.expression.getText(sourceFile);
    let foundKeys = [];
    function findFn(n) {
      if (ts.isVariableDeclaration(n) && n.name.getText(sourceFile) === fnName && n.initializer) {
        if (ts.isArrowFunction(n.initializer) || ts.isFunctionExpression(n.initializer)) {
          if (ts.isObjectLiteralExpression(n.initializer.body) || ts.isParenthesizedExpression(n.initializer.body)) {
            foundKeys = extractKeysFromNode(n.initializer.body, sourceFile);
          } else if (ts.isBlock(n.initializer.body)) {
            for (const st of n.initializer.body.statements) {
              if (ts.isReturnStatement(st) && st.expression) {
                foundKeys = extractKeysFromNode(st.expression, sourceFile);
              }
            }
          }
        }
      } else if (ts.isFunctionDeclaration(n) && n.name && n.name.text === fnName && n.body) {
        for (const st of n.body.statements) {
          if (ts.isReturnStatement(st) && st.expression) {
            foundKeys = extractKeysFromNode(st.expression, sourceFile);
          }
        }
      }
      ts.forEachChild(n, findFn);
    }
    findFn(sourceFile);
    return foundKeys;
  }
  return [];
}

for (const filePath of srcFiles) {
  const content = fs.readFileSync(filePath, 'utf8');
  const sourceFile = ts.createSourceFile(filePath, content, ts.ScriptTarget.Latest, true);

  function visit(node) {
    if (ts.isCallExpression(node)) {
      // Check if call is supabase.rpc(...) or (supabase.rpc as any)(...)
      let isRpc = false;
      const expr = node.expression;
      
      let text = expr.getText(sourceFile);
      if (text.includes('.rpc')) {
        isRpc = true;
      }

      if (isRpc && node.arguments.length > 0) {
        const firstArg = node.arguments[0];
        if (ts.isStringLiteral(firstArg)) {
          const rpcName = firstArg.text;
          const passedKeys = node.arguments.length > 1 ? extractKeysFromNode(node.arguments[1], sourceFile) : [];

          rpcCalls.push({
            file: path.relative(process.cwd(), filePath),
            rpcName,
            passedKeys,
          });
        }
      }
    }
    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
}

const uniqueRpcNames = Array.from(new Set(rpcCalls.map(c => c.rpcName))).sort();

// Query production database for pg_proc functions
const sql = `
SELECT 
    p.proname AS name,
    pg_get_function_arguments(p.oid) AS args,
    pg_get_function_result(p.oid) AS result_type,
    p.pronargs AS num_args,
    p.pronargdefaults AS num_defaults
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
ORDER BY p.proname;
`;

const tmp = path.resolve('scripts/output/pg_proc_signatures.sql');
fs.writeFileSync(tmp, sql, 'utf8');

try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8' });
  const marker = out.indexOf('{');
  if (marker === -1) {
    throw new Error('Could not parse SQL output: ' + out);
  }
  const parsed = JSON.parse(out.slice(marker));
  const procs = parsed.rows || [];

  const dbProcMap = new Map();
  for (const p of procs) {
    if (!dbProcMap.has(p.name)) dbProcMap.set(p.name, []);
    
    // Parse arguments: "p_search text, p_active_state text DEFAULT 'Active'::text, p_limit integer DEFAULT 8"
    const parsedArgs = [];
    if (p.args && p.args.trim()) {
      const parts = p.args.split(',').map(s => s.trim());
      for (const part of parts) {
        const tokens = part.split(/\s+/);
        const argName = tokens[0];
        const hasDefault = part.toLowerCase().includes('default');
        parsedArgs.push({ name: argName, raw: part, hasDefault });
      }
    }
    dbProcMap.get(p.name).push({
      rawArgs: p.args,
      parsedArgs,
      numArgs: p.num_args,
      numDefaults: p.num_defaults,
    });
  }

  let existenceVerifiedCount = 0;
  let argumentKeysVerifiedCount = 0;
  let signatureMismatches = 0;
  const mismatchDetails = [];

  for (const call of rpcCalls) {
    const { rpcName, passedKeys, file } = call;
    if (!dbProcMap.has(rpcName)) {
      signatureMismatches++;
      mismatchDetails.push({ rpcName, file, reason: 'FUNCTION_DOES_NOT_EXIST_IN_DB' });
      continue;
    }

    const overloads = dbProcMap.get(rpcName);
    let matchedOverload = null;

    for (const ol of overloads) {
      const dbArgNames = new Set(ol.parsedArgs.map(a => a.name));
      const dbArgBaseNames = new Set(ol.parsedArgs.map(a => a.name.replace(/^p_/, '')));
      
      // Check if all passed frontend keys exist in the database argument list
      let allPassedKeysValid = true;
      for (const k of passedKeys) {
        if (!dbArgNames.has(k) && !dbArgNames.has('p_' + k) && !dbArgBaseNames.has(k)) {
          allPassedKeysValid = false;
          break;
        }
      }

      // Check if any required arguments (without default) are missing from passed keys
      let allRequiredKeysSupplied = true;
      for (const arg of ol.parsedArgs) {
        if (!arg.hasDefault) {
          const argBase = arg.name.replace(/^p_/, '');
          if (!passedKeys.includes(arg.name) && !passedKeys.includes(argBase) && !passedKeys.includes('p_' + argBase)) {
            allRequiredKeysSupplied = false;
            break;
          }
        }
      }

      if (allPassedKeysValid && allRequiredKeysSupplied) {
        matchedOverload = ol;
        break;
      }
    }

    if (matchedOverload) {
      argumentKeysVerifiedCount++;
    } else {
      signatureMismatches++;
      mismatchDetails.push({
        rpcName,
        file,
        passedKeys,
        availableOverloads: overloads.map(o => o.rawArgs),
        reason: 'ARGUMENT_MISMATCH',
      });
    }
  }

  for (const name of uniqueRpcNames) {
    if (dbProcMap.has(name)) existenceVerifiedCount++;
  }

  console.log('==================================================');
  console.log('REAL LIVE PRODUCTION RPC SIGNATURE VERIFICATION');
  console.log('==================================================');
  console.log(`RPC_REFERENCES_TOTAL: ${uniqueRpcNames.length}`);
  console.log(`RPC_CALL_SITES_TOTAL: ${rpcCalls.length}`);
  console.log(`RPC_EXISTENCE_VERIFIED: ${existenceVerifiedCount}`);
  console.log(`RPC_ARGUMENT_KEYS_VERIFIED: ${argumentKeysVerifiedCount}`);
  console.log(`RPC_SIGNATURE_MISMATCHES: ${signatureMismatches}`);
  console.log('==================================================');

  if (mismatchDetails.length > 0) {
    console.log('Mismatches found:', JSON.stringify(mismatchDetails, null, 2));
    process.exit(1);
  }
} finally {
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
}
