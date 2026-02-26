import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart'; // To access Product model

class ExcelService {
  static Future<void> exportProducts(List<Product> products) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Productos'];
    excel.delete('Sheet1');

    // Headers
    List<String> headers = [
      'Nombre',
      'Marca',
      'Ubicación',
      'Descripción',
      'Unidades por Paquete',
      'Stock',
      'Precio Paquete',
      'Precio Unidad',
      'Precio Paquete Surtido',
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Data
    for (var p in products) {
      sheetObject.appendRow([
        TextCellValue(p.nombre),
        TextCellValue(p.marca),
        TextCellValue(p.ubicacion),
        TextCellValue(p.descripcion),
        IntCellValue(p.unidadesPorPaquete),
        IntCellValue(p.stock),
        DoubleCellValue(p.precioPaquete),
        DoubleCellValue(p.precioUnidad),
        DoubleCellValue(p.precioPaqueteSurtido),
      ]);
    }

    // Save
    var fileBytes = excel.save();
    if (fileBytes != null) {
      Directory tempDir = await getTemporaryDirectory();
      String tempPath = tempDir.path;
      String filePath = '$tempPath/productos_inventario.xlsx';
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);

      await Share.shareXFiles([
        XFile(filePath),
      ], text: 'Exportación de Productos');
    }
  }

  static Future<List<Product>?> importProducts() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      var bytes = File(result.files.single.path!).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);
      List<Product> importedProducts = [];

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table]!;
        // Skip header
        for (int i = 1; i < sheet.maxRows; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty) continue;

          try {
            // Helper local para lectura segura de celdas
            String getValue(int colIndex) {
              if (colIndex >= row.length) return '';
              return row[colIndex]?.value?.toString() ?? '';
            }

            String nombre = getValue(0);
            if (nombre.isEmpty) continue;

            String marca = getValue(1);
            String ubicacion = getValue(2);
            String descripcion = getValue(3);
            int unidadesPorPaquete = int.tryParse(getValue(4)) ?? 1;
            int stock = int.tryParse(getValue(5)) ?? 0;
            double precioPaquete = double.tryParse(getValue(6)) ?? 0.0;
            double precioUnidad = double.tryParse(getValue(7)) ?? 0.0;
            double precioPaqueteSurtido = double.tryParse(getValue(8)) ?? 0.0;

            importedProducts.add(
              Product(
                nombre: nombre,
                marca: marca,
                ubicacion: ubicacion,
                descripcion: descripcion,
                unidadesPorPaquete: unidadesPorPaquete,
                stock: stock,
                precioPaquete: precioPaquete,
                precioUnidad: precioUnidad,
                precioPaqueteSurtido: precioPaqueteSurtido,
                fotoPaths: [],
              ),
            );
          } catch (e) {
            print('Error parsing row $i: $e');
          }
        }
      }
      return importedProducts;
    }
    return null;
  }
}
