import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfReportService {
  static Future<void> generateAndShowReport({
    required String sampleId,
    required String patientId,
    required String patientName,
    required String sampleType,
    required String date,
    required List<Map<String, dynamic>> results,
  }) async {
    final pdf = pw.Document();

    // 🎯 टेस्ट टाइप अनुसार फरक-फरक वैज्ञानिक व्याख्या (Dynamic Interpretation Data)
    String mainInsight = '';
    String methodInfo = '';
    String increasedInText = '';
    String decreasedInText = '';
    String bottomComment = '';

    final typeUpper = sampleType.toUpperCase();

    if (typeUpper == 'URINE' || results.any((r) => r['parameterName'].toString().toLowerCase().contains('urine'))) {
      mainInsight = 'Urine analysis is a vital screening tool to detect metabolic, kidney, and urinary tract disorders.';
      methodInfo = 'Performed via physical examination, chemical reagent strip evaluation, and microscopic sediment analysis.';
      increasedInText = '1. Urinary Tract Infection (UTI)\n2. Diabetes Mellitus (Glucosuria)\n3. Kidney stones or Renal injury';
      decreasedInText = '1. Excessive fluid intake (Dilute)\n2. Diabetes Insipidus\n3. Chronic renal failure (Low Specific Gravity)';
      bottomComment = 'Microscopic findings should be correlated clinically with physical parameters. Transitory changes may occur with diet and hydration.';
    } else if (results.any((r) => r['parameterName'].toString().toLowerCase().contains('sugar') || r['parameterName'].toString().toLowerCase().contains('creatinine') || r['parameterName'].toString().toLowerCase().contains('urea'))) {
      mainInsight = 'Biochemical markers evaluate the functional integrity of kidneys, liver, and glucose metabolism.';
      methodInfo = 'Measured quantitatively on automated clinical chemistry analyzers via enzymatic/spectrophotometric assays.';
      increasedInText = '1. Uncontrolled Diabetes (High Sugar)\n2. Renal Impairment (High Creatinine/Urea)\n3. High protein diet';
      decreasedInText = '1. Insulin overdose / Hypoglycemia\n2. Severe liver disease\n3. Malnutrition or muscle wasting';
      bottomComment = 'Blood sugar values must be interpreted based on patient fasting state (Fasting, Random, or Post-Prandial).';
    } else {
      mainInsight = 'Hemoglobin is the major protein of erythrocytes that transports oxygen from the lungs to peripheral tissues.';
      methodInfo = 'Measured by spectrophotometry on automated platforms after red cell lysis.';
      increasedInText = '1. Dehydration / Severe Vomiting\n2. Polycythemia Vera\n3. Extreme physical exercise';
      decreasedInText = '1. Iron deficiency anemia\n2. Vitamin B12 or Folate deficiency\n3. Anemia of chronic diseases';
      bottomComment = 'The cyanmethemoglobin technique is the international choice. False elevation may occur with hypertriglyceridemia or high WBC.';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 🏥 १. परिमार्जित सफा ल्याब हेडर
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
                        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.SizedBox(height: 4),
                    pw.Text('Bharatpur, Chitwan, Nepal | Tel: 056-593288',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    pw.SizedBox(height: 8),
                    pw.Container(height: 3, color: PdfColors.blue900),
                    pw.Container(height: 1, color: PdfColors.orange800, margin: const pw.EdgeInsets.only(top: 1)),
                    pw.SizedBox(height: 15),
                  ],
                ),
              ),

              // 👥 २. विस्तृत बिरामी र स्याम्पल तालिका
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: [
                  pw.TableRow(
                    children: [
                      _buildMetaCell('Patient Name:', patientName, isBold: true),
                      _buildMetaCell('Registered on:', date),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildMetaCell('Patient ID / UHID:', patientId),
                      _buildMetaCell('Collected on:', date),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildMetaCell('Referred By:', 'Dr. BPKMCH'),
                      _buildMetaCell('Reported on:', date),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildMetaCell('Sample ID:', sampleId, isBold: true),
                      _buildMetaCell('Sample Type:', sampleType),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // 🔬 ३. डिपार्टमेन्ट हेडिङ
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                color: PdfColors.grey300,
                child: pw.Center(
                  child: pw.Text(
                    typeUpper == 'URINE' ? 'CLINICAL PATHOLOGY (URINE EXAMINATION)' : (typeUpper == 'SERUM' ? 'BIOCHEMISTRY' : 'HAEMATOLOGY'),
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                  ),
                ),
              ),
              pw.SizedBox(height: 10),

              // 📊 ४. मुख्य ल्याब रिपोर्ट तालिका
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.5),
                  1: const pw.FlexColumnWidth(0.8),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _buildHeaderCell('TEST'),
                      _buildHeaderCell(''),
                      _buildHeaderCell('VALUE'),
                      _buildHeaderCell('UNIT'),
                      _buildHeaderCell('REFERENCE RANGE'),
                    ],
                  ),
                  ...results.map((r) {
                    final param = (r['parameterName'] ?? '-').toString();
                    final valStr = (r['value'] ?? '-').toString();
                    final unit = (r['unit'] ?? '').toString();
                    final refRange = (r['referenceRange'] ?? '-').toString();
                    
                    String flag = '';
                    if (param.toLowerCase().contains('hemoglobin')) {
                      final double? val = double.tryParse(valStr);
                      if (val != null && val < 12) flag = 'L';
                      if (val != null && val > 15) flag = 'H';
                    }

                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(param)),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6), 
                          child: pw.Text(flag, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                        ),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(valStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(unit)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(refRange)),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 15),

              // 📘 ५. कस्टुम वैज्ञानिक व्याख्या र क्लिनिकल जानकारी
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), color: PdfColors.grey50),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Interpretation / Clinical Insights:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.blue900)),
                    pw.SizedBox(height: 4),
                    pw.Text('• $mainInsight', style: const pw.TextStyle(fontSize: 8.5)),
                    pw.Text('• $methodInfo', style: const pw.TextStyle(fontSize: 8.5)),
                    pw.SizedBox(height: 6),
                    
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Increased in:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.red900)),
                              pw.Text(increasedInText, style: const pw.TextStyle(fontSize: 7.5)),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Decreased in:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.blue900)),
                              pw.Text(decreasedInText, style: const pw.TextStyle(fontSize: 7.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              // 💬 ६. डाइनामिक आन्तरिक कमेन्टहरू
              pw.Text('Comments / Notes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text(bottomComment, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),

              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 15),
                  child: pw.Text('~~~ End of report ~~~', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ),
              ),
              pw.Spacer(),

              // 🖋️ ७. प्रमाणीकरण र हस्ताक्षर
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.SizedBox(width: 130, child: pw.Divider(thickness: 0.5, color: PdfColors.black)),
                      pw.Text('Aliza Thapa Magar', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('CMLT, Lab Incharge (B-5963 MLT)', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.SizedBox(width: 130, child: pw.Divider(thickness: 0.5, color: PdfColors.black)),
                      pw.Text('Consultant Pathologist', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('Bimal Pathology Lab', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // 🎯 यी हेल्पर मेथडहरूलाई क्लास भित्रै सही रूपमा राखियो
  static pw.Widget _buildMetaCell(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Row(
        children: [
          pw.Text('$label ', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static pw.Widget _buildHeaderCell(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.blue900),
      ),
    );
  }
}