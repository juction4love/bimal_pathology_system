import fs from 'node:fs';
import path from 'node:path';

const scriptsDir = 'scripts';
const files = fs.readdirSync(scriptsDir).filter(f => f.endsWith('.js') || f.endsWith('.mjs'));

let updatedFilesCount = 0;

for (const file of files) {
  const filePath = path.join(scriptsDir, file);
  let content = fs.readFileSync(filePath, 'utf8');
  let original = content;

  // 1. Match 'supabase/migrations/00...' or "supabase/migrations/00..."
  content = content.replace(/(['"`])(\.\.\/)?supabase\/migrations\/([0-9]+_[a-zA-Z0-9_-]+\.sql)(['"`])/g, (match, q1, dotdot, migFile, q2) => {
    const activePath = path.join('supabase', 'migrations', migFile);
    const archivePath = path.join('supabase', 'migrations_legacy_archive', migFile);
    if (fs.existsSync(activePath)) {
      return match;
    } else if (fs.existsSync(archivePath)) {
      return `${q1}${dotdot || ''}supabase/migrations_legacy_archive/${migFile}${q2}`;
    }
    return match;
  });

  // 2. Match path.join(..., 'supabase', 'migrations', '00...sql')
  content = content.replace(/(['"`])supabase(['"`]),\s*(['"`])migrations(['"`]),\s*(['"`])([0-9]+_[a-zA-Z0-9_-]+\.sql)(['"`])/g, (match, q1, q2, q3, q4, q5, migFile, q6) => {
    const activePath = path.join('supabase', 'migrations', migFile);
    const archivePath = path.join('supabase', 'migrations_legacy_archive', migFile);
    if (fs.existsSync(activePath)) {
      return match;
    } else if (fs.existsSync(archivePath)) {
      return `'supabase', 'migrations_legacy_archive', '${migFile}'`;
    }
    return match;
  });

  // 3. Match path.resolve(..., 'supabase/migrations/00...sql')
  content = content.replace(/(['"`])\.\.\/supabase\/migrations\/([0-9]+_[a-zA-Z0-9_-]+\.sql)(['"`])/g, (match, q1, migFile, q2) => {
    const activePath = path.join('supabase', 'migrations', migFile);
    const archivePath = path.join('supabase', 'migrations_legacy_archive', migFile);
    if (fs.existsSync(activePath)) {
      return match;
    } else if (fs.existsSync(archivePath)) {
      return `${q1}../supabase/migrations_legacy_archive/${migFile}${q2}`;
    }
    return match;
  });

  if (content !== original) {
    fs.writeFileSync(filePath, content, 'utf8');
    updatedFilesCount++;
    console.log(`Updated ${file}`);
  }
}

console.log(`Updated ${updatedFilesCount} script files.`);
