import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'excel_service.dart';

// --- MODELOS DE DATOS ---

enum VentaEstado {
  SELECCIONANDO, // Vendedora sacando productos (checkboxes azules *)
  VERIFICANDO, // Jefa verificando físicamente (checkboxes verdes, resaltador)
  EMBALANDO, // Envolviendo/embalando productos
  LISTA_ENTREGA, // Lista para entregar (esperando cliente)
  COMPLETADA, // Cliente recogió, venta finalizada
  CANCELADA,
}

class Product {
  final int? id;
  final String nombre;
  final String marca;
  final String ubicacion;
  final String descripcion; // NUEVO: descripción / características
  final int unidadesPorPaquete;
  final int stock;
  final double precioPaquete;
  final double precioUnidad;
  final double precioPaqueteSurtido;
  final List<String> fotoPaths;
  final String? qrCode; // NUEVO: código QR único

  Product({
    this.id,
    required this.nombre,
    required this.marca,
    required this.ubicacion,
    this.descripcion = '',
    required this.unidadesPorPaquete,
    required this.stock,
    required this.precioPaquete,
    required this.precioUnidad,
    this.precioPaqueteSurtido = 0.0,
    this.fotoPaths = const [],
    this.qrCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'marca': marca,
      'ubicacion': ubicacion,
      'descripcion': descripcion,
      'unidades_por_paquete': unidadesPorPaquete,
      'stock': stock,
      'precio_paquete': precioPaquete,
      'precio_unidad': precioUnidad,
      'precio_paquete_surtido': precioPaqueteSurtido,
      'qr_code': qrCode,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      nombre: map['nombre'],
      marca: map['marca'],
      ubicacion: map['ubicacion'],
      descripcion: map['descripcion'] ?? '',
      unidadesPorPaquete: map['unidades_por_paquete'] ?? 1,
      stock: map['stock'] ?? 0,
      precioPaquete: (map['precio_paquete'] as num?)?.toDouble() ?? 0.0,
      precioUnidad: (map['precio_unidad'] as num?)?.toDouble() ?? 0.0,
      precioPaqueteSurtido:
          (map['precio_paquete_surtido'] as num?)?.toDouble() ?? 0.0,
      qrCode: map['qr_code'],
    );
  }

  Product copyWith({List<String>? fotoPaths, int? stock, String? qrCode}) {
    return Product(
      id: id,
      nombre: nombre,
      marca: marca,
      ubicacion: ubicacion,
      descripcion: descripcion,
      unidadesPorPaquete: unidadesPorPaquete,
      stock: stock ?? this.stock,
      precioPaquete: precioPaquete,
      precioUnidad: precioUnidad,
      precioPaqueteSurtido: precioPaqueteSurtido,
      fotoPaths: fotoPaths ?? this.fotoPaths,
      qrCode: qrCode ?? this.qrCode,
    );
  }
}

// NUEVO MODELO PARA LOS ITEMS DE LA VENTA
class VentaItem {
  final int? id;
  final int ventaId;
  final Product producto;
  final int cantidad;
  final double precioVenta;
  final bool esPorPaquete;
  final bool esSurtido; // NUEVO
  bool picked; // Para el vendedor
  bool verificado; // Para el admin

  VentaItem({
    this.id,
    required this.ventaId,
    required this.producto,
    required this.cantidad,
    required this.precioVenta,
    required this.esPorPaquete,
    this.esSurtido = false,
    this.picked = false,
    this.verificado = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'venta_id': ventaId,
      'producto_id': producto.id,
      'cantidad': cantidad,
      'precio_venta': precioVenta,
      'es_por_paquete': esPorPaquete ? 1 : 0,
      'es_surtido': esSurtido ? 1 : 0,
      'picked': picked ? 1 : 0,
      'verificado': verificado ? 1 : 0,
    };
  }

  factory VentaItem.fromMap(Map<String, dynamic> map, Product product) {
    return VentaItem(
      id: map['id'],
      ventaId: map['venta_id'],
      producto: product,
      cantidad: map['cantidad'],
      precioVenta: map['precio_venta'],
      esPorPaquete: map['es_por_paquete'] == 1,
      esSurtido: map['es_surtido'] == 1,
      picked: map['picked'] == 1,
      verificado: map['verificado'] == 1,
    );
  }
}

// NUEVO
class Venta {
  final int? id;
  final int? userId;
  final String nombreCliente;
  final String telefonoCliente;
  final DateTime fecha;
  final double total;
  final double adelanto;
  final VentaEstado estado;
  final List<VentaItem> items;
  final String? nombreVendedor;
  final String? metodoPagoAdelanto;
  final List<String> fotosEmbalaje; // NUEVO

  Venta({
    this.id,
    this.userId,
    required this.nombreCliente,
    required this.telefonoCliente,
    required this.fecha,
    required this.total,
    this.adelanto = 0.0,
    this.estado = VentaEstado.SELECCIONANDO,
    this.items = const [],
    this.nombreVendedor,
    this.metodoPagoAdelanto,
    this.fotosEmbalaje = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'nombre_cliente': nombreCliente,
      'telefono_cliente': telefonoCliente,
      'fecha': fecha.toIso8601String(),
      'total': total,
      'adelanto': adelanto,
      'metodo_pago': metodoPagoAdelanto,
      'estado': estado.toString().split('.').last,
    };
  }

  factory Venta.fromMap(
    Map<String, dynamic> map,
    List<VentaItem> items, {
    List<String> fotosEmbalaje = const [],
  }) {
    return Venta(
      id: map['id'],
      userId: map['user_id'],
      nombreCliente: map['nombre_cliente'] ?? '',
      telefonoCliente: map['telefono_cliente'] ?? '',
      fecha: DateTime.parse(map['fecha']),
      total: map['total'],
      adelanto: map['adelanto'] ?? 0.0,
      metodoPagoAdelanto: map['metodo_pago'],
      fotosEmbalaje: fotosEmbalaje,
      estado: VentaEstado.values.firstWhere(
        (e) => e.toString().split('.').last == map['estado'],
        orElse: () {
          // Migration: convert old state names to new ones
          final oldState = map['estado'];
          if (oldState == 'BORRADOR' || oldState == 'PICKING') {
            return VentaEstado.SELECCIONANDO;
          }
          if (oldState == 'REVISION' || oldState == 'FINAL_CHECK') {
            return VentaEstado.VERIFICANDO;
          }
          if (oldState == 'PACKING') {
            return VentaEstado.EMBALANDO;
          }
          return VentaEstado.SELECCIONANDO; // Default fallback
        },
      ),
      items: items,
      nombreVendedor: map['nombre_vendedor'], // Mapear desde query
    );
  }
}

// --- DATABASE HELPER ---
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'MyDatabase.db');

    return await openDatabase(
      path,
      version: 16,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // PARANOID CHECK: Ensure ventas columns exist
        try {
          await db.execute(
            'ALTER TABLE ventas ADD COLUMN adelanto REAL DEFAULT 0.0',
          );
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE ventas ADD COLUMN metodo_pago TEXT');
        } catch (_) {}
        // PARANOID CHECK: Ensure productos hierarchy columns exist
        try {
          await db.execute(
            'ALTER TABLE productos ADD COLUMN descripcion TEXT DEFAULT ""',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE productos ADD COLUMN paquetes_por_sub_cajon INTEGER DEFAULT 1',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE productos ADD COLUMN sub_cajones_por_cajon INTEGER DEFAULT 1',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE productos ADD COLUMN stock_cajones INTEGER DEFAULT 0',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE productos ADD COLUMN precio_cajon REAL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE productos ADD COLUMN precio_paquete_surtido REAL DEFAULT 0',
          );
        } catch (_) {}
        // PARANOID CHECK: Ensure venta_items flags exist
        try {
          await db.execute(
            'ALTER TABLE venta_items ADD COLUMN es_por_cajon INTEGER DEFAULT 0',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE venta_items ADD COLUMN es_surtido INTEGER DEFAULT 0',
          );
        } catch (_) {}
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT,
        photo_path TEXT,
        biometric_enabled INTEGER DEFAULT 0,
        nombre TEXT,
        telefono TEXT,
        created_at TEXT
      )
    ''');
    // Insert default admin
    await db.insert('users', {
      'username': 'admin',
      'password': '123', // In production, use hashing
      'role': 'admin',
      'photo_path': '',
    });

    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        marca TEXT,
        ubicacion TEXT,
        descripcion TEXT DEFAULT "",
        unidades_por_paquete INTEGER NOT NULL,
        stock INTEGER,
        precio_paquete REAL,
        precio_paquete_surtido REAL DEFAULT 0,
        precio_unidad REAL,
        qr_code TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE product_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        image_path TEXT,
        FOREIGN KEY (product_id) REFERENCES productos (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE ventas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        nombre_cliente TEXT,
        telefono_cliente TEXT,
        fecha TEXT,
        total REAL,
        adelanto REAL DEFAULT 0.0,
        estado TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE venta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER,
        producto_id INTEGER,
        cantidad INTEGER,
        precio_venta REAL,
        es_por_paquete INTEGER,
        picked INTEGER DEFAULT 0,
        verificado INTEGER DEFAULT 0,
        FOREIGN KEY (venta_id) REFERENCES ventas (id) ON DELETE CASCADE,
        FOREIGN KEY (producto_id) REFERENCES productos (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE venta_embalaje_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER,
        image_path TEXT,
        FOREIGN KEY (venta_id) REFERENCES ventas (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE productos ADD COLUMN unidades_por_paquete INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute('''
        CREATE TABLE ventas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre_cliente TEXT,
          telefono_cliente TEXT,
          fecha TEXT,
          total REAL
        )
      ''');
      await db.execute('''
        CREATE TABLE venta_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          venta_id INTEGER,
          producto_id INTEGER,
          cantidad INTEGER,
          precio_venta REAL,
          es_por_paquete INTEGER,
          FOREIGN KEY (venta_id) REFERENCES ventas (id) ON DELETE CASCADE,
          FOREIGN KEY (producto_id) REFERENCES productos (id)
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE ventas ADD COLUMN estado TEXT DEFAULT 'PENDIENTE'",
      );
      await db.execute(
        "ALTER TABLE venta_items ADD COLUMN verificado INTEGER DEFAULT 0",
      );
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT UNIQUE,
          password TEXT,
          role TEXT,
          photo_path TEXT
        )
      ''');
      // Insert default admin
      await db.insert('users', {
        'username': 'admin',
        'password': '123',
        'role': 'admin',
        'photo_path': '',
      });

      // Add user_id to ventas if not exists (simplistic check)
      try {
        await db.execute('ALTER TABLE ventas ADD COLUMN user_id INTEGER');
        await db.execute('CREATE INDEX idx_ventas_user_id ON ventas (user_id)');
      } catch (e) {
        // Column might exist or other error, ignore for now in dev
      }

      // Add picked to venta_items
      await db.execute(
        'ALTER TABLE venta_items ADD COLUMN picked INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      // Re-attempt to add user_id if missed
      try {
        await db.execute('ALTER TABLE ventas ADD COLUMN user_id INTEGER');
        await db.execute('CREATE INDEX idx_ventas_user_id ON ventas (user_id)');
      } catch (e) {
        // Ignore
      }
    }
    if (oldVersion < 8) {
      // Nuclear Option: Recreate table to guarantee user_id exists
      await db.transaction((txn) async {
        // 1. Rename old table
        await txn.execute('ALTER TABLE ventas RENAME TO ventas_old');

        // 2. Create new table
        await txn.execute('''
          CREATE TABLE ventas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            nombre_cliente TEXT,
            telefono_cliente TEXT,
            fecha TEXT,
            total REAL,
            adelanto REAL DEFAULT 0.0,
            estado TEXT,
            FOREIGN KEY (user_id) REFERENCES users (id)
          )
        ''');

        // 3. Copy data
        // Try copying with 'estado' and 'user_id' if they existed, otherwise fallback
        try {
          // Intento copiar todo asumiendo que user_id existía (best effort)
          await txn.execute('''
            INSERT INTO ventas (id, user_id, nombre_cliente, telefono_cliente, fecha, total, estado)
            SELECT id, user_id, nombre_cliente, telefono_cliente, fecha, total, estado FROM ventas_old
          ''');
        } catch (e) {
          try {
            // Si falla user_id, copiamos resto
            await txn.execute('''
                INSERT INTO ventas (id, nombre_cliente, telefono_cliente, fecha, total, estado)
                SELECT id, nombre_cliente, telefono_cliente, fecha, total, estado FROM ventas_old
              ''');
          } catch (e2) {
            // Si falla estado (version muy vieja), copiamos basico
            await txn.execute('''
                  INSERT INTO ventas (id, nombre_cliente, telefono_cliente, fecha, total)
                  SELECT id, nombre_cliente, telefono_cliente, fecha, total FROM ventas_old
                ''');
          }
        }

        // 4. Drop old table
        await txn.execute('DROP TABLE ventas_old');

        // 5. Indices
        await txn.execute(
          'CREATE INDEX idx_ventas_user_idx8 ON ventas (user_id)',
        );
      });
    }
    if (oldVersion < 9) {
      // Add adelanto column
      await db.execute(
        'ALTER TABLE ventas ADD COLUMN adelanto REAL DEFAULT 0.0',
      );
    }
    if (oldVersion < 10) {
      // Add metodo_pago column
      await db.execute('ALTER TABLE ventas ADD COLUMN metodo_pago TEXT');
    }
    if (oldVersion < 11) {
      // Add product hierarchy and description columns
      try {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN descripcion TEXT DEFAULT \"\"',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN paquetes_por_sub_cajon INTEGER DEFAULT 1',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN sub_cajones_por_cajon INTEGER DEFAULT 1',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN stock_cajones INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN precio_cajon REAL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute(
          'ALTER TABLE venta_items ADD COLUMN es_por_cajon INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 13) {
      await db.execute('''
        CREATE TABLE venta_embalaje_images (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          venta_id INTEGER,
          image_path TEXT,
          FOREIGN KEY (venta_id) REFERENCES ventas (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 14) {
      try {
        await db.execute('ALTER TABLE productos ADD COLUMN qr_code TEXT');
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        await db.execute(
          'ALTER TABLE users ADD COLUMN biometric_enabled INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 16) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN nombre TEXT');
        await db.execute('ALTER TABLE users ADD COLUMN telefono TEXT');
        await db.execute('ALTER TABLE users ADD COLUMN created_at TEXT');
        // Inicializar created_at para usuarios existentes
        await db.update('users', {
          'created_at': DateTime.now().toIso8601String(),
        }, where: 'created_at IS NULL');
      } catch (_) {}
    }
  }

  // --- PRODUCTOS ---
  Future<int> insertProduct(Product product) async {
    final db = await database;
    return await db.transaction((txn) async {
      int productId = await txn.insert(
        'productos',
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'product_images',
        where: 'product_id = ?',
        whereArgs: [productId],
      );
      for (String path in product.fotoPaths) {
        await txn.insert('product_images', {
          'product_id': productId,
          'image_path': path,
        });
      }
      return productId;
    });
  }

  Future<void> insertProductsBatch(List<Product> products) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var product in products) {
        int productId = await txn.insert(
          'productos',
          product.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        // Nota: En importación masiva las fotos suelen estar vacías,
        // pero limpiamos por si acaso hay colisiones por ID.
        await txn.delete(
          'product_images',
          where: 'product_id = ?',
          whereArgs: [productId],
        );
        for (String path in product.fotoPaths) {
          await txn.insert('product_images', {
            'product_id': productId,
            'image_path': path,
          });
        }
      }
    });
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return await db.transaction((txn) async {
      int count = await txn.update(
        'productos',
        product.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await txn.delete(
        'product_images',
        where: 'product_id = ?',
        whereArgs: [product.id],
      );
      for (String path in product.fotoPaths) {
        await txn.insert('product_images', {
          'product_id': product.id,
          'image_path': path,
        });
      }
      return count;
    });
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('productos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateProductStock(int productId, int newStock) async {
    final db = await database;
    await db.update(
      'productos',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final maps = await db.query('productos', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    }
    return null;
  }

  // --- USERS ---
  Future<int> insertUser(User user) async {
    final db = await database;
    return await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<User?> getUser(String username, String password) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users');
    return List.generate(maps.length, (i) => User.fromMap(maps[i]));
  }

  Future<void> deleteUser(int id) async {
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateUserBiometrics(int userId, bool enabled) async {
    final db = await database;
    await db.update(
      'users',
      {'biometric_enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final List<Map<String, dynamic>> productMaps = await db.query('productos');
    List<Product> products = [];
    for (var pMap in productMaps) {
      final List<Map<String, dynamic>> imageMaps = await db.query(
        'product_images',
        where: 'product_id = ?',
        whereArgs: [pMap['id']],
      );
      List<String> imagePaths = imageMaps
          .map((iMap) => iMap['image_path'] as String)
          .toList();
      products.add(Product.fromMap(pMap).copyWith(fotoPaths: imagePaths));
    }
    return products;
  }

  // --- VENTAS ---
  Future<int> insertVenta(Venta venta) async {
    final db = await database;
    return db.transaction((txn) async {
      int ventaId = await txn.insert('ventas', venta.toMap());

      // PARANOID FIX: Force update user_id to ensure it is saved
      if (venta.userId != null) {
        await txn.rawUpdate('UPDATE ventas SET user_id = ? WHERE id = ?', [
          venta.userId,
          ventaId,
        ]);
      }

      // Explicitly update adelanto to ensure persistence
      if (venta.adelanto > 0) {
        await txn.rawUpdate('UPDATE ventas SET adelanto = ? WHERE id = ?', [
          venta.adelanto,
          ventaId,
        ]);
        // Also update payment method for adelanto
        if (venta.metodoPagoAdelanto != null) {
          await txn.rawUpdate(
            'UPDATE ventas SET metodo_pago = ? WHERE id = ?',
            [venta.metodoPagoAdelanto, ventaId],
          );
        }
      }

      for (var item in venta.items) {
        await txn.insert(
          'venta_items',
          item.copyWith(ventaId: ventaId).toMap(),
        );
      }
      return ventaId;
    });
  }

  Future<List<Venta>> getVentas() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> ventasMaps = await db.rawQuery('''
        SELECT v.*, u.username as nombre_vendedor 
        FROM ventas v 
        LEFT JOIN users u ON v.user_id = u.id 
        ORDER BY v.fecha DESC
      ''');

      List<Venta> ventas = [];

      for (var vMap in ventasMaps) {
        final List<Map<String, dynamic>> itemsMaps = await db.query(
          'venta_items',
          where: 'venta_id = ?',
          whereArgs: [vMap['id']],
        );
        List<VentaItem> items = [];
        for (var iMap in itemsMaps) {
          Product? product = await getProductById(iMap['producto_id']);
          if (product != null) {
            items.add(
              VentaItem(
                id: iMap['id'],
                ventaId: vMap['id'],
                producto: product,
                cantidad: iMap['cantidad'],
                precioVenta: iMap['precio_venta'],
                esPorPaquete: iMap['es_por_paquete'] == 1,
                esSurtido: iMap['es_surtido'] == 1,
                verificado: iMap['verificado'] == 1,
                picked: iMap['picked'] == 1,
              ),
            );
          }
        }

        final List<Map<String, dynamic>> imagesMaps = await db.query(
          'venta_embalaje_images',
          where: 'venta_id = ?',
          whereArgs: [vMap['id']],
        );
        List<String> fotosEmbalaje = imagesMaps
            .map((img) => img['image_path'] as String)
            .toList();

        ventas.add(Venta.fromMap(vMap, items, fotosEmbalaje: fotosEmbalaje));
      }
      return ventas;
    } catch (e) {
      debugPrint('Error getting ventas: $e');
      return [];
    }
  }

  Future<void> updateVentaItemVerificado(int itemId, bool verificado) async {
    final db = await database;
    await db.update(
      'venta_items',
      {'verificado': verificado ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> updateVentaItemPicked(int itemId, bool picked) async {
    final db = await database;
    await db.update(
      'venta_items',
      {'picked': picked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> updateVentaEstado(int ventaId, VentaEstado estado) async {
    final db = await database;
    await db.update(
      'ventas',
      {'estado': estado.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [ventaId],
    );
  }

  Future<void> deleteVenta(int ventaId) async {
    final db = await database;
    await db.delete('ventas', where: 'id = ?', whereArgs: [ventaId]);
  }

  Future<int> insertVentaItem(VentaItem item) async {
    final db = await database;
    return await db.insert('venta_items', item.toMap());
  }

  Future<void> updateVentaItemQuantity(int itemId, int newQuantity) async {
    final db = await database;
    await db.update(
      'venta_items',
      {'cantidad': newQuantity},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> deleteVentaItem(int itemId) async {
    final db = await database;
    await db.delete('venta_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> updateVentaTotal(int ventaId, double newTotal) async {
    final db = await database;
    await db.update(
      'ventas',
      {'total': newTotal},
      where: 'id = ?',
      whereArgs: [ventaId],
    );
  }

  // --- IMÁGENES DE EMBALAJE ---
  Future<void> insertVentaEmbalajeImage(int ventaId, String imagePath) async {
    final db = await database;
    await db.insert('venta_embalaje_images', {
      'venta_id': ventaId,
      'image_path': imagePath,
    });
  }

  Future<void> deleteVentaEmbalajeImage(int ventaId, String imagePath) async {
    final db = await database;
    await db.delete(
      'venta_embalaje_images',
      where: 'venta_id = ? AND image_path = ?',
      whereArgs: [ventaId, imagePath],
    );
  }
}

// --- MODELOS DE USUARIO ---

enum UserRole { admin, warehouse_full, warehouse_restricted, sales }

class User {
  final int? id;
  final String username;
  final String password;
  final UserRole role;
  final String photoPath;
  final bool biometricEnabled;
  final String? nombre;
  final String? telefono;
  final DateTime createdAt;

  User({
    this.id,
    required this.username,
    required this.password,
    required this.role,
    required this.photoPath,
    this.biometricEnabled = false,
    this.nombre,
    this.telefono,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'role': role.toString().split('.').last,
      'photo_path': photoPath,
      'biometric_enabled': biometricEnabled ? 1 : 0,
      'nombre': nombre,
      'telefono': telefono,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      password: map['password'],
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == map['role'],
        orElse: () => UserRole.sales,
      ),
      photoPath: map['photo_path'] ?? '',
      biometricEnabled: (map['biometric_enabled'] as int?) == 1,
      nombre: map['nombre'],
      telefono: map['telefono'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? password,
    UserRole? role,
    String? photoPath,
    bool? biometricEnabled,
    String? nombre,
    String? telefono,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      photoPath: photoPath ?? this.photoPath,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// --- MODELO PRODUCTO ---

// Extensión para facilitar la creación de copia de VentaItem
extension VentaItemCopyWith on VentaItem {
  VentaItem copyWith({int? ventaId}) {
    return VentaItem(
      id: id,
      ventaId: ventaId ?? this.ventaId,
      producto: producto,
      cantidad: cantidad,
      precioVenta: precioVenta,
      esPorPaquete: esPorPaquete,
      verificado: verificado,
    );
  }
}

// --- SERVICIOS ---

class BiometricService {
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  Future<bool> holdsBiometrics() async {
    try {
      return await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await auth.authenticate(
        localizedReason: 'Autentíquese para ingresar al sistema',
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> saveCredentials(String username, String password) async {
    await storage.write(key: 'user_id', value: username);
    await storage.write(key: 'password', value: password);
  }

  Future<Map<String, String>?> getCredentials() async {
    String? username = await storage.read(key: 'user_id');
    String? password = await storage.read(key: 'password');
    if (username != null && password != null) {
      return {'username': username, 'password': password};
    }
    return null;
  }

  Future<void> clearCredentials() async {
    await storage.delete(key: 'user_id');
    await storage.delete(key: 'password');
  }
}

// --- PROVIDERS ---

class UserProvider with ChangeNotifier {
  User? _currentUser;
  User? get currentUser => _currentUser;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.role == UserRole.admin;
  bool get canViewAllSales => isAdmin;
  bool get canManageInventory =>
      isAdmin || _currentUser?.role == UserRole.warehouse_full;
  bool get isWarehouseFull => _currentUser?.role == UserRole.warehouse_full;
  bool get isWarehouseRestricted =>
      _currentUser?.role == UserRole.warehouse_restricted;
  bool get isSales => _currentUser?.role == UserRole.sales;

  Future<bool> login(String username, String password) async {
    final user = await _dbHelper.getUser(username, password);
    if (user != null) {
      _currentUser = user;
      print(
        'DEBUG: Login successful for user: ${user.username}, ID: ${user.id}, Role: ${user.role}',
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  Future<void> addUser(User user) async {
    await _dbHelper.insertUser(user);
    notifyListeners();
  }

  Future<List<User>> getAllUsers() async {
    return await _dbHelper.getAllUsers();
  }

  Future<void> deleteUser(int id) async {
    await _dbHelper.deleteUser(id);
    notifyListeners();
  }

  // --- LÓGICA BIOMÉTRICA ---
  final BiometricService _biometricService = BiometricService();

  Future<bool> canUseBiometrics() async {
    return await _biometricService.holdsBiometrics();
  }

  Future<bool> loginWithBiometrics() async {
    bool authenticated = await _biometricService.authenticate();
    if (authenticated) {
      final creds = await _biometricService.getCredentials();
      if (creds != null) {
        return await login(creds['username']!, creds['password']!);
      }
    }
    return false;
  }

  Future<void> updateBiometricPreference(bool enabled, String password) async {
    if (_currentUser == null) return;
    final updatedUser = _currentUser!.copyWith(biometricEnabled: enabled);
    await _dbHelper.updateUserBiometrics(updatedUser.id!, enabled);
    _currentUser = updatedUser;

    if (enabled) {
      await _biometricService.saveCredentials(_currentUser!.username, password);
    } else {
      await _biometricService.clearCredentials();
    }
    notifyListeners();
  }

  Future<void> updateUserProfile(User updatedUser) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      updatedUser.toMap(),
      where: 'id = ?',
      whereArgs: [updatedUser.id],
    );
    _currentUser = updatedUser;
    notifyListeners();
  }
}

class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  String _searchQuery = '';

  List<Product> get products => _filteredProducts;
  Product? getProductById(int id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  ProductProvider() {
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    final dbHelper = DatabaseHelper();
    _products = await dbHelper.getProducts();
    _filterProducts();
    notifyListeners();
  }

  void _filterProducts() {
    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(_products);
    } else {
      final queryLower = _searchQuery.toLowerCase();
      _filteredProducts = _products.where((product) {
        final nombreLower = product.nombre.toLowerCase();
        final marcaLower = product.marca.toLowerCase();
        return nombreLower.contains(queryLower) ||
            marcaLower.contains(queryLower);
      }).toList();
    }
  }

  Future<void> addProduct(Product product) async {
    final dbHelper = DatabaseHelper();
    // Generar QR si no tiene uno (best practice)
    Product productToInsert = product;
    if (product.qrCode == null || product.qrCode!.isEmpty) {
      productToInsert = product.copyWith(qrCode: const Uuid().v4());
    }
    await dbHelper.insertProduct(productToInsert);
    await fetchProducts();
  }

  Future<void> addProducts(List<Product> products) async {
    final dbHelper = DatabaseHelper();
    List<Product> productsToInsert = [];

    for (var product in products) {
      Product p = product;
      if (p.qrCode == null || p.qrCode!.isEmpty) {
        p = p.copyWith(qrCode: const Uuid().v4());
      }
      productsToInsert.add(p);
    }

    await dbHelper.insertProductsBatch(productsToInsert);
    await fetchProducts();
  }

  Future<void> updateProduct(Product product) async {
    final dbHelper = DatabaseHelper();

    // Seguridad QR: Asegurar que nunca se pierda el QR original
    Product productToUpdate = product;
    if (product.qrCode == null || product.qrCode!.isEmpty) {
      final existingProduct = await dbHelper.getProductById(product.id!);
      if (existingProduct != null && existingProduct.qrCode != null) {
        productToUpdate = product.copyWith(qrCode: existingProduct.qrCode);
      } else {
        // Solo si realmente nunca tuvo uno (falló la creación original)
        productToUpdate = product.copyWith(qrCode: const Uuid().v4());
      }
    }

    await dbHelper.updateProduct(productToUpdate);
    await fetchProducts();
  }

  Future<void> deleteProduct(int id) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.deleteProduct(id);
    await fetchProducts();
  }

  Future<void> updateStock(int productId, int newStock) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.updateProductStock(productId, newStock);
    // Actualiza el producto localmente para reflejar el cambio de inmediato
    final productIndex = _products.indexWhere((p) => p.id == productId);
    if (productIndex != -1) {
      _products[productIndex] = _products[productIndex].copyWith(
        stock: newStock,
      );
      _filterProducts();
      notifyListeners();
    }
  }

  void search(String query) {
    _searchQuery = query;
    _filterProducts();
    notifyListeners();
  }
}

class VentasProvider with ChangeNotifier {
  List<Venta> _ventas = [];
  List<Venta> get ventas => _ventas;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  VentasProvider() {
    fetchVentas();
  }

  Future<void> fetchVentas() async {
    _ventas = await _dbHelper.getVentas();
    notifyListeners();
  }

  // Filter by user ID
  List<Venta> getVentasByUser(int userId) {
    return _ventas.where((v) => v.userId == userId).toList();
  }

  // Filter by status
  List<Venta> getVentasByStatus(VentaEstado status) {
    return _ventas.where((v) => v.estado == status).toList();
  }

  // Get lists pending approval (for Admin)
  List<Venta> getPendingApprovals() {
    return _ventas
        .where(
          (v) =>
              v.estado == VentaEstado.VERIFICANDO ||
              v.estado == VentaEstado.LISTA_ENTREGA,
        )
        .toList();
  }

  Future<void> addVenta(Venta venta) async {
    await _dbHelper.insertVenta(venta);
    await fetchVentas();
  }

  Future<void> updateItemVerificado(int itemId, bool verificado) async {
    await _dbHelper.updateVentaItemVerificado(itemId, verificado);
    await fetchVentas();
  }

  Future<void> updateItemPicked(int itemId, bool picked) async {
    await _dbHelper.updateVentaItemPicked(itemId, picked);
    await fetchVentas();
  }

  Future<void> updateVentaStatus(int ventaId, VentaEstado newStatus) async {
    await _dbHelper.updateVentaEstado(ventaId, newStatus);
    await fetchVentas();
  }

  Future<void> completarVenta(
    Venta venta,
    ProductProvider productProvider,
  ) async {
    // 1. Consolidar descuentos por ID de producto para evitar datos obsoletos
    final Map<int, int> deductions = {};
    for (var item in venta.items) {
      int unitsPerItem = 1;
      if (item.esSurtido || item.esPorPaquete) {
        unitsPerItem = item.producto.unidadesPorPaquete;
      }
      int totalUnits = item.cantidad * unitsPerItem;
      deductions[item.producto.id!] =
          (deductions[item.producto.id!] ?? 0) + totalUnits;
    }

    // 2. Aplicar descuentos consolidados usando el stock más reciente
    for (var entry in deductions.entries) {
      final productId = entry.key;
      final totalToReduce = entry.value;

      try {
        // Buscamos el producto en la lista del provider para tener el stock actual real
        final currentProduct = productProvider.products.firstWhere(
          (p) => p.id == productId,
        );
        int newStock = currentProduct.stock - totalToReduce;
        await productProvider.updateStock(productId, newStock);
      } catch (e) {
        debugPrint('Error actualizando stock para producto $productId: $e');
        // Si el producto no se encuentra o hay otro error, continuamos con el siguiente
      }
    }

    await _dbHelper.updateVentaEstado(venta.id!, VentaEstado.COMPLETADA);
    await fetchVentas();
  }

  Future<void> deleteVenta(int ventaId) async {
    await _dbHelper.deleteVenta(ventaId);
    await fetchVentas();
  }

  Future<void> addItemToVenta(
    Venta venta,
    Product product,
    int quantity, {
    bool isPackage = false,
    bool isSurtido = false,
  }) async {
    double price = product.precioUnidad;
    if (isSurtido) {
      price = product.precioPaqueteSurtido;
    } else if (isPackage) {
      price = product.precioPaquete;
    }

    final newItem = VentaItem(
      ventaId: venta.id!,
      producto: product,
      cantidad: quantity,
      precioVenta: price,
      esPorPaquete: isPackage,
      esSurtido: isSurtido,
    );
    await _dbHelper.insertVentaItem(newItem);

    // Recalculate total
    double newTotal = venta.total + (newItem.cantidad * newItem.precioVenta);
    await _dbHelper.updateVentaTotal(venta.id!, newTotal);

    await fetchVentas();
  }

  Future<void> updateItemQuantity(
    Venta venta,
    VentaItem item,
    int newQuantity,
  ) async {
    await _dbHelper.updateVentaItemQuantity(item.id!, newQuantity);

    // Recalculate total (complex because we need to iterate all items or adjust delta)
    // Easier to recalculate from scratch or adjust by diff
    double diff = (newQuantity - item.cantidad) * item.precioVenta;
    double newTotal = venta.total + diff;
    await _dbHelper.updateVentaTotal(venta.id!, newTotal);

    await fetchVentas();
  }

  Future<void> deleteVentaItem(Venta venta, VentaItem item) async {
    await _dbHelper.deleteVentaItem(item.id!);

    double reduction = item.cantidad * item.precioVenta;
    double newTotal = venta.total - reduction;
    await _dbHelper.updateVentaTotal(venta.id!, newTotal);

    await fetchVentas();
  }

  Future<void> removeItemFromVenta(Venta venta, VentaItem item) async {
    await _dbHelper.deleteVentaItem(item.id!);

    // Recalculate total
    double newTotal = venta.total - (item.cantidad * item.precioVenta);
    await _dbHelper.updateVentaTotal(venta.id!, newTotal);

    await fetchVentas();
  }

  // --- FOTOS DE EMBALAJE ---
  Future<void> addPackingPhoto(int ventaId, String imagePath) async {
    await _dbHelper.insertVentaEmbalajeImage(ventaId, imagePath);
    await fetchVentas();
  }

  Future<void> removePackingPhoto(int ventaId, String imagePath) async {
    await _dbHelper.deleteVentaEmbalajeImage(ventaId, imagePath);
    await fetchVentas();
  }

  Future<int> getUserSalesCount(int userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM ventas WHERE user_id = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => UserProvider()),
        ChangeNotifierProvider(create: (context) => ProductProvider()),
        ChangeNotifierProvider(create: (context) => VentasProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// --- APLICACIÓN PRINCIPAL Y NAVEGACIÓN ---

// Login Screen
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingrese usuario y contraseña')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final success = await userProvider.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (success) {
      // Navigate to main app
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario o contraseña incorrectos')),
      );
    }
  }

  Future<void> _loginBiometric() async {
    setState(() => _isLoading = true);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final success = await userProvider.loginWithBiometrics();
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de autenticación biométrica o no configurada'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2, size: 100, color: Colors.indigo.shade700),
              const SizedBox(height: 24),
              const Text(
                'Sistema de Inventario',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 400,
                child: TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person),
                  ),
                  onSubmitted: (_) => _login(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 400,
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  onSubmitted: (_) => _login(),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 400,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Iniciar Sesión'),
                ),
              ),
              if (!_isLoading) ...[
                const SizedBox(height: 24),
                FutureBuilder<bool>(
                  future: Provider.of<UserProvider>(
                    context,
                    listen: false,
                  ).canUseBiometrics(),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return IconButton(
                        icon: const Icon(
                          Icons.fingerprint,
                          size: 70,
                          color: Colors.indigo,
                        ),
                        onPressed: _loginBiometric,
                        tooltip: 'Iniciar sesión con huella',
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Main Layout with BottomNavigationBar
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        if (!userProvider.isLoggedIn) {
          return const LoginScreen();
        }

        // Build navigation items based on role
        final List<Widget> screens = [
          const ProductListScreen(),
          const SalesListScreen(),
          if (userProvider.isAdmin) const ApprovalsScreen(),
          if (userProvider.isAdmin) const UserManagementScreen(),
          const ProfileScreen(), // Profile screen
        ];

        final List<BottomNavigationBarItem> navItems = [
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Ventas',
          ),
          if (userProvider.isAdmin)
            const BottomNavigationBarItem(
              icon: Icon(Icons.approval_outlined),
              activeIcon: Icon(Icons.approval),
              label: 'Aprobaciones',
            ),
          if (userProvider.isAdmin)
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Usuarios',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventario App'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: Text(
                    userProvider.currentUser?.username ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: IndexedStack(index: _selectedIndex, children: screens),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            items: navItems,
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.indigo.shade800,
            unselectedItemColor: Colors.grey.shade600,
          ),
        );
      },
    );
  }
}

// Profile Screen
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, VentasProvider>(
      builder: (context, userProvider, ventasProvider, child) {
        final user = userProvider.currentUser;
        if (user == null) return const SizedBox();

        final accountAge = DateTime.now().difference(user.createdAt).inDays;

        return FutureBuilder<int>(
          future: ventasProvider.getUserSalesCount(user.id!),
          builder: (context, snapshot) {
            final salesCount = snapshot.data ?? 0;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 70,
                          backgroundColor: Colors.indigo.shade800,
                          backgroundImage: user.photoPath.isNotEmpty
                              ? FileImage(File(user.photoPath))
                              : null,
                          child: user.photoPath.isEmpty
                              ? Text(
                                  user.username.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 56,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: Colors.indigo,
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  _pickProfilePhoto(context, userProvider),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      user.nombre ?? user.username,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _getRoleDisplayName(user.role),
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (user.telefono != null && user.telefono!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.phone,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              user.telefono!,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatCard(
                          'Ventas Generadas',
                          salesCount.toString(),
                          Icons.receipt_long,
                        ),
                        _buildStatCard(
                          'Días de la Cuenta',
                          accountAge.toString(),
                          Icons.calendar_today,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: FutureBuilder<bool>(
                          future: userProvider.canUseBiometrics(),
                          builder: (context, snapshot) {
                            if (snapshot.data == true) {
                              return SwitchListTile(
                                secondary: const Icon(Icons.fingerprint),
                                title: const Text('Ingreso con Huella'),
                                subtitle: const Text(
                                  'Permitir iniciar sesión usando biometría',
                                ),
                                value: user.biometricEnabled,
                                onChanged: (bool value) async {
                                  if (value) {
                                    _showPasswordConfirmDialog(
                                      context,
                                      userProvider,
                                    );
                                  } else {
                                    await userProvider
                                        .updateBiometricPreference(false, '');
                                  }
                                },
                              );
                            }
                            return const ListTile(
                              leading: Icon(
                                Icons.fingerprint,
                                color: Colors.grey,
                              ),
                              title: Text('Huella no disponible'),
                              subtitle: Text(
                                'Su dispositivo no soporta biometría',
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          userProvider.logout();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar Sesión'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 150,
        child: Column(
          children: [
            Icon(icon, color: Colors.indigo, size: 32),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto(
    BuildContext context,
    UserProvider userProvider,
  ) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = p.basename(pickedFile.path);
      final savedImage = await File(
        pickedFile.path,
      ).copy('${appDir.path}/$fileName');

      final user = userProvider.currentUser;
      if (user != null) {
        final updatedUser = user.copyWith(photoPath: savedImage.path);
        await userProvider.updateUserProfile(updatedUser);
      }
    }
  }

  void _showPasswordConfirmDialog(
    BuildContext context,
    UserProvider userProvider,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Para habilitar el ingreso con huella, ingrese su contraseña actual para guardarla de forma segura.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim() ==
                  userProvider.currentUser?.password) {
                await userProvider.updateBiometricPreference(
                  true,
                  controller.text.trim(),
                );
                if (context.mounted) Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contraseña incorrecta')),
                );
              }
            },
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    );
  }

  String _getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.warehouse_full:
        return 'Almacén - Experto';
      case UserRole.warehouse_restricted:
        return 'Almacén - Nuevo';
      case UserRole.sales:
        return 'Ventas';
    }
  }
}

// User Management Screen (Admin only)
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<User> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final users = await userProvider.getAllUsers();
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  Future<void> _showUserFormDialog({User? user}) async {
    final isEditing = user != null;
    final usernameController = TextEditingController(text: user?.username);
    final passwordController = TextEditingController(text: user?.password);
    final nombreController = TextEditingController(text: user?.nombre);
    final telefonoController = TextEditingController(text: user?.telefono);
    UserRole selectedRole = user?.role ?? UserRole.sales;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar Usuario' : 'Agregar Usuario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nombreController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo (opcional)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: telefonoController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (opcional)',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: UserRole.values.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(_getRoleDisplayName(role)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (usernameController.text.isEmpty ||
                    passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor complete todos los campos'),
                    ),
                  );
                  return;
                }

                final userProvider = Provider.of<UserProvider>(
                  context,
                  listen: false,
                );

                if (isEditing) {
                  final updatedUser = user.copyWith(
                    username: usernameController.text,
                    password: passwordController.text,
                    role: selectedRole,
                    nombre: nombreController.text.isNotEmpty
                        ? nombreController.text
                        : null,
                    telefono: telefonoController.text.isNotEmpty
                        ? telefonoController.text
                        : null,
                  );
                  await userProvider.updateUserProfile(updatedUser);
                } else {
                  final newUser = User(
                    username: usernameController.text,
                    password: passwordController.text,
                    role: selectedRole,
                    photoPath: '',
                    nombre: nombreController.text.isNotEmpty
                        ? nombreController.text
                        : null,
                    telefono: telefonoController.text.isNotEmpty
                        ? telefonoController.text
                        : null,
                  );
                  await userProvider.addUser(newUser);
                }

                Navigator.pop(context);
                _loadUsers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEditing ? 'Usuario actualizado' : 'Usuario agregado',
                      ),
                    ),
                  );
                }
              },
              child: Text(isEditing ? 'Guardar' : 'Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUserDetailModal(User user) async {
    final ventasProvider = Provider.of<VentasProvider>(context, listen: false);
    final accountAge = DateTime.now().difference(user.createdAt).inDays;
    final salesCount = await ventasProvider.getUserSalesCount(user.id!);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.indigo.shade800,
                  backgroundImage: user.photoPath.isNotEmpty
                      ? FileImage(File(user.photoPath))
                      : null,
                  child: user.photoPath.isEmpty
                      ? Text(
                          user.username.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nombre ?? user.username,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(_getRoleDisplayName(user.role)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.indigo),
                  onPressed: () {
                    Navigator.pop(context);
                    _showUserFormDialog(user: user);
                  },
                ),
              ],
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Usuario'),
              subtitle: Text(user.username),
            ),
            if (user.telefono != null)
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Teléfono'),
                subtitle: Text(user.telefono!),
              ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Antigüedad'),
              subtitle: Text('$accountAge días'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Ventas/Listas Generadas'),
              subtitle: Text(salesCount.toString()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(User user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Usuario'),
        content: Text('¿Está seguro de eliminar a "${user.username}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && user.id != null) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      await userProvider.deleteUser(user.id!);
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Usuario eliminado')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? const Center(
              child: Text(
                'No hay usuarios registrados',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final isCurrentUser =
                    Provider.of<UserProvider>(
                      context,
                      listen: false,
                    ).currentUser?.id ==
                    user.id;

                return Card(
                  child: ListTile(
                    onTap: () => _showUserDetailModal(user),
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.shade800,
                      backgroundImage: user.photoPath.isNotEmpty
                          ? FileImage(File(user.photoPath))
                          : null,
                      child: user.photoPath.isEmpty
                          ? Text(
                              user.username.substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            )
                          : null,
                    ),
                    title: Text(
                      user.nombre ?? user.username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(_getRoleDisplayName(user.role)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (user.id != null)
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showUserFormDialog(user: user),
                          ),
                        if (isCurrentUser)
                          Chip(
                            label: const Text('Tú'),
                            backgroundColor: Colors.indigo.shade100,
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteUser(user),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserFormDialog(),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text(
          'Agregar Usuario',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
      ),
    );
  }

  String _getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.warehouse_full:
        return 'Almacén - Experto';
      case UserRole.warehouse_restricted:
        return 'Almacén - Nuevo';
      case UserRole.sales:
        return 'Ventas';
    }
  }
}

// Approvals Screen (Admin only)
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aprobaciones y Revisiones')),
      body: Consumer<VentasProvider>(
        builder: (context, provider, child) {
          final pendingList = provider.getPendingApprovals();

          if (pendingList.isEmpty) {
            return const Center(
              child: Text(
                'No hay listas pendientes de revisión.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: pendingList.length,
            itemBuilder: (context, index) {
              final venta = pendingList[index];
              return Card(
                color: venta.estado == VentaEstado.VERIFICANDO
                    ? Colors.orange[50]
                    : Colors.green[50],
                child: ListTile(
                  title: Text(
                    venta.nombreCliente,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy HH:mm').format(venta.fecha)}\nTotal: Bs. ${venta.total.toStringAsFixed(2)}\nEstado: ${_getEstadoDisplayName(venta.estado)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SaleDetailScreen(venta: venta),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _getEstadoDisplayName(VentaEstado estado) {
    switch (estado) {
      case VentaEstado.VERIFICANDO:
        return 'Verificando (Jefa)';
      case VentaEstado.LISTA_ENTREGA:
        return 'Lista para Entregar';
      case VentaEstado.SELECCIONANDO:
        return 'Seleccionando';
      case VentaEstado.EMBALANDO:
        return 'Embalando';
      case VentaEstado.COMPLETADA:
        return 'Completada';
      default:
        return 'Estado Desconocido';
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventario App',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.indigo.shade800,
          elevation: 4,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.indigo.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.indigo.shade700, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.indigo.shade800,
          unselectedItemColor: Colors.grey.shade600,
          elevation: 10,
        ),
      ),
      home: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          return userProvider.isLoggedIn
              ? const MainLayout()
              : const LoginScreen();
        },
      ),
    );
  }
}

// Old HomeScreen removed - now using MainLayout with Drawer

// --- PANTALLAS PRINCIPALES ---

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});
  // ... (Esta pantalla y sus métodos auxiliares permanecen casi iguales)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Exportar a Excel',
            onPressed: () {
              final products = Provider.of<ProductProvider>(
                context,
                listen: false,
              ).products;
              ExcelService.exportProducts(products);
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Importar desde Excel',
            onPressed: () async {
              final newProducts = await ExcelService.importProducts();
              if (newProducts != null && newProducts.isNotEmpty) {
                if (!context.mounted) return;
                bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirmar Importación'),
                    content: Text(
                      'Se han encontrado ${newProducts.length} productos. ¿Deseas agregarlos al inventario?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Importar'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  if (!context.mounted) return;
                  // Mostrar loader
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    await Provider.of<ProductProvider>(
                      context,
                      listen: false,
                    ).addProducts(newProducts);

                    if (!context.mounted) return;
                    Navigator.pop(context); // Cerrar loader
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${newProducts.length} productos importados con éxito',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    Navigator.pop(context); // Cerrar loader
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Error de Importación'),
                        content: Text(
                          'No se pudieron agregar los productos: $e',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Entendido'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) => Provider.of<ProductProvider>(
                context,
                listen: false,
              ).search(value),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o marca...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: Consumer<ProductProvider>(
              builder: (context, provider, child) {
                if (provider.products.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay productos. ¡Agrega uno!',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
                  itemCount: provider.products.length,
                  itemBuilder: (context, index) {
                    final product = provider.products[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showProductDetailModal(context, product),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: product.fotoPaths.isNotEmpty
                                    ? Image.file(
                                        File(product.fotoPaths.first),
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                _buildErrorIcon(),
                                      )
                                    : _buildErrorIcon(),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.nombre,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Marca: ${product.marca}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    if (product.descripcion.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4.0,
                                        ),
                                        child: Text(
                                          product.descripcion,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Stock: ${(product.stock ~/ product.unidadesPorPaquete)} P + ${(product.stock % product.unidadesPorPaquete)} U',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blueGrey[700],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    Text(
                                      'Paq: Bs. ${product.precioPaquete.toStringAsFixed(2)} / Uni: Bs. ${product.precioUnidad.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green[700],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (Provider.of<UserProvider>(
                                context,
                                listen: false,
                              ).canManageInventory)
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              EditProductScreen(
                                                product: product,
                                              ),
                                        ),
                                      );
                                    } else if (value == 'delete') {
                                      _showDeleteConfirmationDialog(
                                        context,
                                        product,
                                      );
                                    }
                                  },
                                  itemBuilder: (BuildContext context) =>
                                      <PopupMenuEntry<String>>[
                                        const PopupMenuItem<String>(
                                          value: 'edit',
                                          child: ListTile(
                                            leading: Icon(Icons.edit),
                                            title: Text('Editar'),
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: ListTile(
                                            leading: Icon(Icons.delete),
                                            title: Text('Eliminar'),
                                          ),
                                        ),
                                      ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton:
          Provider.of<UserProvider>(context).canManageInventory
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddProductScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Agregar',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.indigo.shade800,
            )
          : null,
    );
  }

  Widget _buildErrorIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: const Icon(Icons.inventory_2, color: Colors.white, size: 40),
    );
  }

  // Pega esto al final de tu clase ProductListScreen
  void _showProductDetailModal(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            int _currentCarouselIndex = 0;
            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              title: Text(
                product.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.fotoPaths.isNotEmpty)
                      Column(
                        children: [
                          CarouselSlider(
                            options: CarouselOptions(
                              height: 250,
                              viewportFraction: 1.0,
                              enlargeCenterPage: false,
                              onPageChanged: (index, reason) {
                                setState(() {
                                  _currentCarouselIndex = index;
                                });
                              },
                            ),
                            items: product.fotoPaths.map((path) {
                              return Builder(
                                builder: (BuildContext context) {
                                  return Container(
                                    width: MediaQuery.of(context).size.width,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2.0,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                FullScreenImageScreen(
                                                  imagePath: path,
                                                ),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          12.0,
                                        ),
                                        child: Image.file(
                                          File(path),
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, o, s) => const Icon(
                                            Icons.error,
                                            size: 50,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: product.fotoPaths.asMap().entries.map((
                              entry,
                            ) {
                              return Container(
                                width: _currentCarouselIndex == entry.key
                                    ? 10.0
                                    : 8.0,
                                height: _currentCarouselIndex == entry.key
                                    ? 10.0
                                    : 8.0,
                                margin: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                  horizontal: 4.0,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.indigo.withOpacity(
                                    _currentCarouselIndex == entry.key
                                        ? 0.9
                                        : 0.4,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 250,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 80,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (product.descripcion.isNotEmpty) ...[
                      const Text(
                        'Características:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.descripcion,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                    ],
                    const SizedBox(height: 10),
                    _buildDetailRow(Icons.label, 'Marca', product.marca),
                    _buildDetailRow(
                      Icons.place,
                      'Ubicación',
                      product.ubicacion,
                    ),
                    const Divider(height: 32),
                    const Text(
                      'Información de Empaque',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      Icons.reorder,
                      'Cajita/Paquete',
                      '1 Paquete = ${product.unidadesPorPaquete} Unidades',
                    ),
                    const Divider(height: 32),
                    const Text(
                      'Stock Disponible',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            Icons.inventory,
                            'Stock Total',
                            '${product.stock ~/ product.unidadesPorPaquete} Paquetes cerrados',
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Producto Suelto:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${(product.stock % product.unidadesPorPaquete)} Unidades',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 32),
                    const Text(
                      'Precios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPriceRow(
                      'Por Paquete',
                      product.precioPaquete,
                      Colors.green.shade800,
                    ),
                    if (product.precioPaqueteSurtido > 0)
                      _buildPriceRow(
                        'Por Paq. Surtido',
                        product.precioPaqueteSurtido,
                        Colors.teal,
                      ),
                    _buildPriceRow(
                      'Por Unidad',
                      product.precioUnidad,
                      Colors.green.shade800,
                    ),
                    const Divider(height: 32),
                    const Text(
                      'Código identificación único (QR)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (product.qrCode != null)
                      Center(
                        child: Column(
                          children: [
                            QrImageView(
                              data: product.qrCode!,
                              version: QrVersions.auto,
                              size: 180.0,
                              backgroundColor: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              product.qrCode!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const Center(
                        child: Text(
                          'No hay código QR generado para este producto.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar', style: TextStyle(fontSize: 16)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 15, color: Colors.black),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double price, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            'Bs. ${price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Eliminación'),
          content: Text(
            '¿Estás seguro de que quieres eliminar "${product.nombre}"?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Provider.of<ProductProvider>(
                  context,
                  listen: false,
                ).deleteProduct(product.id!);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${product.nombre}" eliminado.'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- FORMULARIOS DE PRODUCTO ---

abstract class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key});
}

abstract class ProductFormScreenState<T extends ProductFormScreen>
    extends State<T> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _marcaController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _descripcionController = TextEditingController(); // NUEVO
  final _unidadesController = TextEditingController();
  final _paquetesStockController = TextEditingController();
  final _unidadesSueltasStockController = TextEditingController();
  final _precioPaqueteController = TextEditingController();
  final _precioPaqueteSurtidoController = TextEditingController(
    text: '0',
  ); // NUEVO
  final _precioUnidadController = TextEditingController();
  final List<XFile> _imageFiles = [];
  List<String> _existingImagePaths = [];

  @override
  void dispose() {
    _nombreController.dispose();
    _marcaController.dispose();
    _ubicacionController.dispose();
    _descripcionController.dispose(); // NUEVO
    _unidadesController.dispose();
    _paquetesStockController.dispose();
    _unidadesSueltasStockController.dispose();
    _precioPaqueteController.dispose();
    _precioPaqueteSurtidoController.dispose(); // NUEVO
    _precioUnidadController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 70,
      );
      if (image != null) setState(() => _imageFiles.add(image));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  void _removeNewImage(int index) =>
      setState(() => _imageFiles.removeAt(index));
  void _removeExistingImage(int index) =>
      setState(() => _existingImagePaths.removeAt(index));

  Future<void> saveProduct();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          this is _AddProductScreenState
              ? 'Agregar Producto'
              : 'Editar Producto',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Producto',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa un nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _marcaController,
                decoration: const InputDecoration(labelText: 'Marca'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa una marca' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ubicacionController,
                decoration: const InputDecoration(
                  labelText: 'Ubicación (Piso/Estante)',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa una ubicación' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _unidadesController,
                decoration: const InputDecoration(
                  labelText: 'Unidades por Paquete',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa las unidades';
                  if (int.tryParse(v) == null || int.parse(v) < 1)
                    return 'Debe ser un número mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _paquetesStockController,
                      decoration: const InputDecoration(
                        labelText: 'Stock (Paquetes)',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _unidadesSueltasStockController,
                      decoration: const InputDecoration(
                        labelText: 'Stock (Unidades Sueltas)',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _precioPaqueteController,
                decoration: const InputDecoration(
                  labelText: 'Precio por Paquete (Bs.)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa un precio';
                  if (double.tryParse(v) == null)
                    return 'Ingresa un número válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _precioPaqueteSurtidoController,
                decoration: const InputDecoration(
                  labelText: 'Precio Paquete Surtido (Opcional)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _precioUnidadController,
                decoration: const InputDecoration(
                  labelText: 'Precio por Unidad (Bs.)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa un precio';
                  if (double.tryParse(v) == null)
                    return 'Ingresa un número válido';
                  return null;
                },
              ),

              // ─── DESCRIPCIÓN ───────────────────────────────────────
              const SizedBox(height: 32),
              const Text(
                'Descripción / Características',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descripcionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción (Opcional)',
                  hintText: 'Ej: La bolsa contiene 10 unidades...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 32),
              const Text(
                "Fotos del Producto",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: (_imageFiles.isEmpty && _existingImagePaths.isEmpty)
                    ? const Center(child: Text('Añade una o más fotos.'))
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        children: [
                          ..._existingImagePaths.asMap().entries.map(
                            (e) => _buildImageThumbnail(
                              File(e.value),
                              () => _removeExistingImage(e.key),
                            ),
                          ),
                          ..._imageFiles.asMap().entries.map(
                            (e) => _buildImageThumbnail(
                              File(e.value.path),
                              () => _removeNewImage(e.key),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      label: const Text(
                        'Tomar Foto',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Galería',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: saveProduct,
                child: Text(
                  this is _AddProductScreenState
                      ? 'Guardar Producto'
                      : 'Guardar Cambios',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(File imageFile, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              imageFile,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (c, o, s) => Container(
                width: 100,
                height: 100,
                color: Colors.grey.shade300,
                child: const Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddProductScreen extends ProductFormScreen {
  const AddProductScreen({super.key});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ProductFormScreenState<AddProductScreen> {
  @override
  Future<void> saveProduct() async {
    if (!super._formKey.currentState!.validate()) return;
    if (super._imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, toma al menos una foto del producto.'),
        ),
      );
      return;
    }

    final List<String> savedImagePaths = [];
    final Directory appDir = await getApplicationDocumentsDirectory();
    for (var file in super._imageFiles) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
      final savedPath = p.join(appDir.path, fileName);
      await File(file.path).copy(savedPath);
      savedImagePaths.add(savedPath);
    }

    int unidadesPorPaquete = int.parse(super._unidadesController.text);
    int paquetes = int.tryParse(super._paquetesStockController.text) ?? 0;
    int unidadesSueltas =
        int.tryParse(super._unidadesSueltasStockController.text) ?? 0;
    int totalStock = (paquetes * unidadesPorPaquete) + unidadesSueltas;

    final newProduct = Product(
      nombre: super._nombreController.text,
      marca: super._marcaController.text,
      ubicacion: super._ubicacionController.text,
      descripcion: super._descripcionController.text,
      unidadesPorPaquete: unidadesPorPaquete,
      stock: totalStock,
      precioPaquete: double.parse(super._precioPaqueteController.text),
      precioPaqueteSurtido:
          double.tryParse(super._precioPaqueteSurtidoController.text) ?? 0.0,
      precioUnidad: double.parse(super._precioUnidadController.text),
      fotoPaths: savedImagePaths,
    );

    if (!mounted) return;
    await Provider.of<ProductProvider>(
      context,
      listen: false,
    ).addProduct(newProduct);
    Navigator.pop(context);
  }
}

class EditProductScreen extends ProductFormScreen {
  final Product product;
  const EditProductScreen({super.key, required this.product});
  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState
    extends ProductFormScreenState<EditProductScreen> {
  @override
  void initState() {
    super.initState();
    super._nombreController.text = widget.product.nombre;
    super._marcaController.text = widget.product.marca;
    super._ubicacionController.text = widget.product.ubicacion;
    super._descripcionController.text = widget.product.descripcion;
    super._unidadesController.text = widget.product.unidadesPorPaquete
        .toString();
    super._precioPaqueteSurtidoController.text = widget
        .product
        .precioPaqueteSurtido
        .toString();
    int stock = widget.product.stock;
    int unidadesPorPaquete = widget.product.unidadesPorPaquete;
    if (unidadesPorPaquete > 0) {
      super._paquetesStockController.text = (stock ~/ unidadesPorPaquete)
          .toString();
      super._unidadesSueltasStockController.text = (stock % unidadesPorPaquete)
          .toString();
    } else {
      super._paquetesStockController.text = '0';
      super._unidadesSueltasStockController.text = stock.toString();
    }
    super._precioPaqueteController.text = widget.product.precioPaquete
        .toString();
    super._precioUnidadController.text = widget.product.precioUnidad.toString();
    super._existingImagePaths = List.from(widget.product.fotoPaths);
  }

  @override
  Future<void> saveProduct() async {
    if (!super._formKey.currentState!.validate()) return;
    if (super._imageFiles.isEmpty && super._existingImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El producto debe tener al menos una foto.'),
        ),
      );
      return;
    }

    final finalImagePaths = List<String>.from(super._existingImagePaths);
    final Directory appDir = await getApplicationDocumentsDirectory();
    for (var file in super._imageFiles) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
      final savedPath = p.join(appDir.path, fileName);
      await File(file.path).copy(savedPath);
      finalImagePaths.add(savedPath);
    }

    int unidadesPorPaquete = int.parse(super._unidadesController.text);
    int paquetes = int.tryParse(super._paquetesStockController.text) ?? 0;
    int unidadesSueltas =
        int.tryParse(super._unidadesSueltasStockController.text) ?? 0;
    int totalStock = (paquetes * unidadesPorPaquete) + unidadesSueltas;

    final updatedProduct = Product(
      id: widget.product.id,
      nombre: super._nombreController.text,
      marca: super._marcaController.text,
      ubicacion: super._ubicacionController.text,
      descripcion: super._descripcionController.text,
      unidadesPorPaquete: unidadesPorPaquete,
      stock: totalStock,
      precioPaquete: double.parse(super._precioPaqueteController.text),
      precioPaqueteSurtido:
          double.tryParse(super._precioPaqueteSurtidoController.text) ?? 0.0,
      precioUnidad: double.parse(super._precioUnidadController.text),
      fotoPaths: finalImagePaths,
      qrCode: widget.product.qrCode, // PRESERVAR EL QR ORIGINAL
    );
    if (!mounted) return;
    await Provider.of<ProductProvider>(
      context,
      listen: false,
    ).updateProduct(updatedProduct);
    Navigator.pop(context);
  }
}

// --- PANTALLAS DE VENTAS ---

class SalesListScreen extends StatelessWidget {
  const SalesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Listas')),
      body: Consumer<VentasProvider>(
        builder: (context, provider, child) {
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );

          print(
            'DEBUG: SalesListScreen - User: ${userProvider.currentUser?.username} (ID: ${userProvider.currentUser?.id})',
          );
          print('DEBUG: CanViewAll: ${userProvider.canViewAllSales}');
          print('DEBUG: Total ventas in provider: ${provider.ventas.length}');

          final displayedVentas = userProvider.canViewAllSales
              ? provider.ventas
              : provider.getVentasByUser(userProvider.currentUser!.id!);

          if (displayedVentas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No hay listas registradas.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            itemCount: displayedVentas.length,
            itemBuilder: (context, index) {
              final venta = displayedVentas[index];
              final isCompleted = venta.estado == VentaEstado.COMPLETADA;
              final isDraft = venta.estado == VentaEstado.SELECCIONANDO;

              Color cardColor;
              if (isCompleted) {
                cardColor = Colors.white;
              } else if (isDraft) {
                cardColor = Colors.grey[100]!;
              } else {
                cardColor = Colors.amber[50]!;
              }

              Color statusColor;
              String statusText;
              if (isCompleted) {
                statusColor = Colors.green;
                statusText = 'COMPLETADA';
              } else if (isDraft) {
                statusColor = Colors.blueGrey;
                statusText = 'PARA REVISIÓN';
              } else {
                statusColor = Colors.orange;
                statusText = 'EN PROCESO';
              }

              return Card(
                color: cardColor,
                child: ListTile(
                  title: Text(
                    venta.nombreCliente,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy HH:mm').format(venta.fecha)}\n'
                    'Total: Bs. ${venta.total.toStringAsFixed(2)}\n'
                    '${venta.adelanto > 0 ? "Adelanto: Bs. ${venta.adelanto.toStringAsFixed(2)}\n" : ""}'
                    '${venta.adelanto > 0 ? "Saldo: Bs. ${(venta.total - venta.adelanto).toStringAsFixed(2)}\n" : ""}'
                    'Estado: ${_getEstadoDisplayName(venta.estado)}\n'
                    '${_getProgressInfo(venta)}'
                    'Vendedor: ${venta.nombreVendedor ?? "Desconocido"}',
                    style: const TextStyle(height: 1.3),
                  ),
                  isThreeLine: true,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SaleDetailScreen(venta: venta),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateSaleScreen()),
        ),
        label: const Text('Nueva Lista', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.indigo.shade800,
      ),
    );
  }

  String _getEstadoDisplayName(VentaEstado estado) {
    switch (estado) {
      case VentaEstado.SELECCIONANDO:
        return 'Seleccionando Productos';
      case VentaEstado.VERIFICANDO:
        return 'Verificando (Jefa)';
      case VentaEstado.EMBALANDO:
        return 'Embalando';
      case VentaEstado.LISTA_ENTREGA:
        return 'Listo para Entregar';
      case VentaEstado.COMPLETADA:
        return 'Completada';
      case VentaEstado.CANCELADA:
        return 'Cancelada';
    }
  }

  String _getProgressInfo(Venta venta) {
    if (venta.estado == VentaEstado.SELECCIONANDO) {
      final pickedCount = venta.items.where((i) => i.picked).length;
      return 'Seleccionado: $pickedCount/${venta.items.length}\n';
    } else if (venta.estado == VentaEstado.VERIFICANDO) {
      final verifiedCount = venta.items.where((i) => i.verificado).length;
      return 'Verificado: $verifiedCount/${venta.items.length}\n';
    } else if (venta.estado == VentaEstado.EMBALANDO) {
      return 'En proceso de embalaje\n';
    } else if (venta.estado == VentaEstado.LISTA_ENTREGA) {
      return 'Esperando cliente\n';
    } else if (venta.estado == VentaEstado.COMPLETADA) {
      return 'Entregado\n';
    }
    return '';
  }
}

class CreateSaleScreen extends StatefulWidget {
  const CreateSaleScreen({super.key});
  @override
  State<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CreateSaleScreenState extends State<CreateSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreClienteController = TextEditingController();
  final _telefonoClienteController = TextEditingController();
  final _adelantoController = TextEditingController();
  final List<VentaItem> _cart = [];
  double _total = 0.0;
  bool _isRestoring = false;
  String? _metodoPagoAdelanto; // AÑADIDO: Estado para método de pago

  @override
  void initState() {
    super.initState();
    _loadDraft();
    _nombreClienteController.addListener(_saveDraft);
    _telefonoClienteController.addListener(_saveDraft);
    _adelantoController.addListener(() {
      setState(() {});
      _saveDraft();
    });
  }

  @override
  void dispose() {
    _nombreClienteController.removeListener(_saveDraft);
    _telefonoClienteController.removeListener(_saveDraft);
    _adelantoController.removeListener(
      _saveDraft,
    ); // Listener wrapper removal isn't straightforward, but disposal handles it.
    _nombreClienteController.dispose();
    _telefonoClienteController.dispose();
    _adelantoController.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    if (_isRestoring) return;

    final prefs = await SharedPreferences.getInstance();
    final draftData = {
      'nombre': _nombreClienteController.text,
      'telefono': _telefonoClienteController.text,
      'adelanto': _adelantoController.text,
      'metodo_pago': _metodoPagoAdelanto, // Guardar método de pago
      'items': _cart
          .map(
            (item) => {
              'productId': item.producto.id,
              'quantity': item.cantidad,
              'isPackage': item.esPorPaquete,
            },
          )
          .toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    await prefs.setString('draft_sale_v1', jsonEncode(draftData));
  }

  Future<void> _loadDraft() async {
    _isRestoring = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftString = prefs.getString('draft_sale_v1');

      if (draftString != null && draftString.isNotEmpty) {
        final draftData = jsonDecode(draftString);

        _nombreClienteController.text = draftData['nombre'] ?? '';
        _telefonoClienteController.text = draftData['telefono'] ?? '';
        _adelantoController.text = draftData['adelanto'] ?? '';
        _metodoPagoAdelanto =
            draftData['metodo_pago']; // Restaurar método de pago

        final List<dynamic> itemsData = draftData['items'] ?? [];
        final productProvider = Provider.of<ProductProvider>(
          context,
          listen: false,
        );

        // Ensure products are loaded
        if (productProvider.products.isEmpty) {
          await productProvider.fetchProducts();
        }

        List<VentaItem> restoredItems = [];

        for (var itemData in itemsData) {
          final productId = itemData['productId'];
          final product = productProvider.getProductById(productId);

          if (product != null) {
            final quantity = itemData['quantity'];
            final isPackage = itemData['isPackage'];
            final price = isPackage
                ? product.precioPaquete
                : product.precioUnidad;

            restoredItems.add(
              VentaItem(
                ventaId: 0,
                producto: product,
                cantidad: quantity,
                precioVenta: price,
                esPorPaquete: isPackage,
              ),
            );
          }
        }

        if (mounted) {
          setState(() {
            _cart.clear();
            _cart.addAll(restoredItems);
            _calculateTotal();
          });

          if (_cart.isNotEmpty || _nombreClienteController.text.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Borrador recuperado automáticamente'),
                backgroundColor: Colors.blueGrey,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error restoring draft: $e');
    } finally {
      _isRestoring = false;
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_sale_v1');
  }

  Future<void> _discardDraft() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar borrador?'),
        content: const Text(
          'Esto borrará todos los datos no guardados de esta lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _clearDraft();
      if (!mounted) return;
      setState(() {
        _nombreClienteController.clear();
        _telefonoClienteController.clear();
        _adelantoController.clear();
        _metodoPagoAdelanto = null; // Limpiar método de pago
        _cart.clear();
        _calculateTotal();
      });
    }
  }

  void _addToCart(
    Product product,
    int quantity, {
    bool isPackage = false,
    bool isSurtido = false,
  }) {
    double price = product.precioUnidad;
    int unitsPerItem = 1;

    if (isSurtido) {
      price = product.precioPaqueteSurtido;
      unitsPerItem = product.unidadesPorPaquete;
    } else if (isPackage) {
      price = product.precioPaquete;
      unitsPerItem = product.unidadesPorPaquete;
    }

    final stockNeeded = quantity * unitsPerItem;

    if (stockNeeded > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock insuficiente. Disponible: ${product.stock} unidades.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _cart.add(
        VentaItem(
          ventaId: 0,
          producto: product,
          cantidad: quantity,
          precioVenta: price,
          esPorPaquete: isPackage,
          esSurtido: isSurtido,
        ),
      );
      _calculateTotal();
      _saveDraft();
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
      _calculateTotal();
      _saveDraft();
    });
  }

  void _calculateTotal() {
    _total = _cart.fold(
      0.0,
      (sum, item) => sum + (item.cantidad * item.precioVenta),
    );
  }

  void _showAddProductDialog() {
    final productProvider = Provider.of<ProductProvider>(
      context,
      listen: false,
    );
    // Asegurarse de que la búsqueda esté limpia antes de abrir el diálogo
    productProvider.search('');

    showDialog(
      context: context,
      builder: (context) {
        // Usar un StatefulBuilder para que el diálogo tenga su propio estado
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Seleccionar Producto'),
              contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              content: SizedBox(
                width: double.maxFinite,
                height:
                    MediaQuery.of(context).size.height *
                    0.6, // Altura para dar espacio
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- BARRA DE BÚSQUEDA ---
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: TextField(
                        autofocus: true,
                        onChanged: (value) {
                          // Llama a la búsqueda del provider y usa setState del diálogo
                          // para que se actualice solo el contenido del diálogo.
                          setState(() {
                            productProvider.search(value);
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre o marca...',
                          prefixIcon: Icon(Icons.search),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    // --- LISTA DE PRODUCTOS ---
                    Expanded(
                      // Consumer para reconstruir la lista cuando cambian los productos filtrados
                      child: Consumer<ProductProvider>(
                        builder: (context, provider, child) {
                          if (provider.products.isEmpty) {
                            return const Center(
                              child: Text('No se encontraron productos.'),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: provider.products.length,
                            itemBuilder: (context, index) {
                              final product = provider.products[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  title: Text(
                                    product.nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Stock: ${(product.stock ~/ product.unidadesPorPaquete)} Paquetes + ${(product.stock % product.unidadesPorPaquete)} Unidades',
                                      ),
                                      Text(
                                        'Paq: Bs. ${product.precioPaquete.toStringAsFixed(2)} / Uni: Bs. ${product.precioUnidad.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: Colors.green[800],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _showQuantityDialog(product);
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Limpiar la búsqueda al cerrar
                    productProvider.search('');
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQuantityDialog(Product product) {
    final quantityController = TextEditingController(text: '1');
    String saleType = 'paquete'; // 'unidad', 'paquete', 'surtido', 'cajon'

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(product.nombre),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: quantityController,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tipo de Venta:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: saleType,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'unidad',
                        child: Text('Unidad suelta'),
                      ),
                      const DropdownMenuItem(
                        value: 'paquete',
                        child: Text('Paquete cerrado'),
                      ),
                      if (product.precioPaqueteSurtido > 0)
                        const DropdownMenuItem(
                          value: 'surtido',
                          child: Text('Paquete Surtido'),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => saleType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildPriceHint(product, saleType),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final quantity = int.tryParse(quantityController.text) ?? 0;
                    if (quantity > 0) {
                      _addToCart(
                        product,
                        quantity,
                        isPackage: saleType == 'paquete',
                        isSurtido: saleType == 'surtido',
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Agregar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPriceHint(Product product, String saleType) {
    double price = 0;
    String detail = '';
    switch (saleType) {
      case 'unidad':
        price = product.precioUnidad;
        detail = '1 unidad';
        break;
      case 'paquete':
        price = product.precioPaquete;
        detail = '${product.unidadesPorPaquete} u';
        break;
      case 'surtido':
        price = product.precioPaqueteSurtido;
        detail = '${product.unidadesPorPaquete} u (Surtido)';
        break;
    }
    return Text(
      'Precio: Bs. ${price.toStringAsFixed(2)} ($detail)',
      style: const TextStyle(
        fontSize: 13,
        color: Colors.indigo,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _getPackagingLabel(VentaItem item) {
    if (item.esSurtido) return 'Paq. Surtido';
    return item.esPorPaquete ? 'Paquete' : 'Unidad';
  }

  Future<void> _saveVenta() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Añade al menos un producto a la venta.')),
      );
      return;
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final currentUser = userProvider.currentUser;

      if (currentUser == null || currentUser.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ERROR: No hay usuario autenticado. Reinicia sesión.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final adelanto = double.tryParse(_adelantoController.text) ?? 0.0;

      // Validación de método de pago si hay adelanto
      if (adelanto > 0 && _metodoPagoAdelanto == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Por favor seleccione el método de pago del adelanto.',
            ),
          ),
        );
        return;
      }

      final newVenta = Venta(
        nombreCliente: _nombreClienteController.text,
        telefonoCliente: _telefonoClienteController.text,
        fecha: DateTime.now(),
        total: _total,
        adelanto: adelanto,
        metodoPagoAdelanto: adelanto > 0
            ? _metodoPagoAdelanto
            : null, // Pasar método de pago
        estado: VentaEstado.SELECCIONANDO,
        userId: currentUser.id,
        items: _cart,
        nombreVendedor: currentUser.username,
      );

      await Provider.of<VentasProvider>(
        context,
        listen: false,
      ).addVenta(newVenta);

      // Clear draft on success
      await _clearDraft();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lista guardada (User: ${currentUser.username})'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error: $e'); // Keep minimal logging
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Lista de Pedido'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Descartar Borrador',
            onPressed: _discardDraft,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Datos del Cliente',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombreClienteController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Cliente',
                ),
                validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoClienteController,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (Opcional)',
                ),
                keyboardType: TextInputType.phone,
              ),
              const Divider(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Productos en la Lista',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_shopping_cart,
                      color: Colors.indigo,
                    ),
                    onPressed: _showAddProductDialog,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _cart.isEmpty
                  ? const Text(
                      'Aún no hay productos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.producto.nombre),
                            subtitle: Text(
                              '${item.cantidad} x ${_getPackagingLabel(item)} @ Bs. ${item.precioVenta.toStringAsFixed(2)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Bs. ${(item.cantidad * item.precioVenta).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removeFromCart(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              const Divider(height: 40),
              Text(
                'Monto del Adelanto',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adelantoController,
                decoration: const InputDecoration(
                  labelText: 'Adelanto (Bs.) - Opcional',
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (_adelantoController.text.isNotEmpty &&
                  (double.tryParse(_adelantoController.text) ?? 0) > 0) ...[
                const SizedBox(height: 16),
                const Text(
                  'Método de Pago del Adelanto:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('QR/Billetera'),
                        value: 'QR',
                        groupValue: _metodoPagoAdelanto,
                        onChanged: (value) {
                          setState(() {
                            _metodoPagoAdelanto = value;
                          });
                          _saveDraft();
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Efectivo'),
                        value: 'EFECTIVO',
                        groupValue: _metodoPagoAdelanto,
                        onChanged: (value) {
                          setState(() {
                            _metodoPagoAdelanto = value;
                          });
                          _saveDraft();
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 40),
              Text(
                'Total: Bs. ${_total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Adelanto: Bs. ${(double.tryParse(_adelantoController.text) ?? 0).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Saldo: Bs. ${(_total == 0 ? 0 : (_total - (double.tryParse(_adelantoController.text) ?? 0))).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color:
                      (_total > 0 &&
                          (_total -
                                  (double.tryParse(_adelantoController.text) ??
                                      0)) >
                              0)
                      ? Colors.red[700]
                      : Colors.green[700],
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _saveVenta,
                child: const Text('Generar Lista'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SaleDetailScreen extends StatefulWidget {
  final Venta venta;
  const SaleDetailScreen({super.key, required this.venta});
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  // Removed _items and initState to use Provider state directly

  Future<void> _sendToVerification() async {
    await Provider.of<VentasProvider>(
      context,
      listen: false,
    ).updateVentaStatus(widget.venta.id!, VentaEstado.VERIFICANDO);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Productos enviados a verificación.'),
        backgroundColor: Colors.blue,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _sendToPacking() async {
    await Provider.of<VentasProvider>(
      context,
      listen: false,
    ).updateVentaStatus(widget.venta.id!, VentaEstado.EMBALANDO);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Productos verificados. Proceder a embalar.'),
        backgroundColor: Colors.orange,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _markPackingComplete() async {
    await Provider.of<VentasProvider>(
      context,
      listen: false,
    ).updateVentaStatus(widget.venta.id!, VentaEstado.LISTA_ENTREGA);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Embalaje completo. Lista para entregar.'),
        backgroundColor: Colors.purple,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _confirmDelivery() async {
    final ventasProvider = Provider.of<VentasProvider>(context, listen: false);
    final productProvider = Provider.of<ProductProvider>(
      context,
      listen: false,
    );
    await ventasProvider.completarVenta(widget.venta, productProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Venta completada y stock actualizado.'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _deleteVenta() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Lista?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      await Provider.of<VentasProvider>(
        context,
        listen: false,
      ).deleteVenta(widget.venta.id!);
      if (!mounted) return;
      Navigator.pop(context); // Return to list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista eliminada correctamente')),
      );
    }
  }

  void _showProductSelectorDialog() {
    final productProvider = Provider.of<ProductProvider>(
      context,
      listen: false,
    );
    productProvider.search('');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Agregar Producto'),
              contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: TextField(
                        autofocus: true,
                        onChanged: (value) {
                          setState(() {
                            productProvider.search(value);
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Buscar...',
                          prefixIcon: Icon(Icons.search),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Consumer<ProductProvider>(
                        builder: (context, provider, child) {
                          if (provider.products.isEmpty) {
                            return const Center(
                              child: Text('No hay resultados.'),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: provider.products.length,
                            itemBuilder: (context, index) {
                              final product = provider.products[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  title: Text(
                                    product.nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Paq: Bs. ${product.precioPaquete} / Uni: Bs. ${product.precioUnidad}',
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _showQuantityDialog(product);
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQuantityDialog(Product product) {
    final quantityController = TextEditingController(text: '1');
    String saleType = 'paquete'; // 'unidad', 'paquete', 'surtido', 'cajon'

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(product.nombre),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: quantityController,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tipo de Venta:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: saleType,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'unidad',
                        child: Text('Unidad suelta'),
                      ),
                      const DropdownMenuItem(
                        value: 'paquete',
                        child: Text('Paquete cerrado'),
                      ),
                      if (product.precioPaqueteSurtido > 0)
                        const DropdownMenuItem(
                          value: 'surtido',
                          child: Text('Paquete Surtido'),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => saleType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildPriceHint(product, saleType),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final quantity = int.tryParse(quantityController.text) ?? 0;
                    if (quantity > 0) {
                      final provider = Provider.of<VentasProvider>(
                        context,
                        listen: false,
                      );
                      final currentVenta = provider.ventas.firstWhere(
                        (v) => v.id == widget.venta.id,
                      );

                      await provider.addItemToVenta(
                        currentVenta,
                        product,
                        quantity,
                        isPackage: saleType == 'paquete',
                        isSurtido: saleType == 'surtido',
                      );
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Agregar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPriceHint(Product product, String saleType) {
    double price = 0;
    String detail = '';
    switch (saleType) {
      case 'unidad':
        price = product.precioUnidad;
        detail = '1 unidad';
        break;
      case 'paquete':
        price = product.precioPaquete;
        detail = '${product.unidadesPorPaquete} unidades';
        break;
      case 'surtido':
        price = product.precioPaqueteSurtido;
        detail = '${product.unidadesPorPaquete} unidades (Surtido)';
        break;
    }
    return Text(
      'Precio: Bs. ${price.toStringAsFixed(2)} ($detail)',
      style: const TextStyle(
        fontSize: 13,
        color: Colors.indigo,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Future<void> _confirmDeleteItem(VentaItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar ${item.producto.nombre}?'),
        content: const Text(
          'Esta acción quitará el producto de la lista permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      final provider = Provider.of<VentasProvider>(context, listen: false);
      // Re-fetch current venta to ensure we have the latest state for total calculation
      final currentVenta = provider.ventas.firstWhere(
        (v) => v.id == widget.venta.id,
      );

      await provider.deleteVentaItem(currentVenta, item);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto eliminado de la lista')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final ventasProvider = Provider.of<VentasProvider>(context);

    // Find current venta state or fallback to widget.venta (safe handling for deletions)
    final venta = ventasProvider.ventas.firstWhere(
      (v) => v.id == widget.venta.id,
      orElse: () => widget.venta,
    );
    final items = venta.items;

    final isAdmin = userProvider.currentUser?.role == UserRole.admin;
    final currentUserId = userProvider.currentUser?.id;
    final isOwner = venta.userId == currentUserId;

    // Determine what actions are available based on state and role
    final canPick =
        (isOwner || isAdmin) && venta.estado == VentaEstado.SELECCIONANDO;
    final canVerify = isAdmin && venta.estado == VentaEstado.VERIFICANDO;
    final canPack =
        (isOwner || isAdmin) && venta.estado == VentaEstado.EMBALANDO;
    final canDeliver = isAdmin && venta.estado == VentaEstado.LISTA_ENTREGA;
    final isCompleted = venta.estado == VentaEstado.COMPLETADA;

    final allPicked = items.every((item) => item.picked);
    final allVerified = items.every((item) => item.verificado);

    return Scaffold(
      appBar: AppBar(
        title: Text('Detalle de Lista #${widget.venta.id}'),
        actions: [
          if (canPick) // Sólo si es editable (SELECCIONANDO y dueño/admin)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Eliminar Lista',
              onPressed: _deleteVenta,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cliente: ${venta.nombreCliente}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (venta.telefonoCliente.isNotEmpty)
              Text(
                'Teléfono: ${venta.telefonoCliente}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            Text(
              'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(venta.fecha)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Estado: ${_getEstadoDisplayName(venta.estado)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _getEstadoColor(venta.estado),
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lista de Productos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (canPick)
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: Colors.indigo,
                      size: 28,
                    ),
                    tooltip: 'Agregar Producto',
                    onPressed: _showProductSelectorDialog,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildItemTile(
                  venta,
                  item,
                  canPick,
                  canVerify,
                  isCompleted,
                );
              },
            ),
            const Divider(height: 30),
            Text(
              'Total: Bs. ${venta.total.toStringAsFixed(2)}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Adelanto: Bs. ${venta.adelanto.toStringAsFixed(2)} ${venta.metodoPagoAdelanto != null ? "(${venta.metodoPagoAdelanto})" : ""}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.green[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Saldo Pendiente: Bs. ${(venta.total == 0 ? 0 : (venta.total - venta.adelanto)).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: (venta.total > 0 && (venta.total - venta.adelanto) > 0)
                    ? Colors.red[700]
                    : Colors.green[700],
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            _buildPackingPhotosSection(venta, canPack, isAdmin),

            const SizedBox(height: 30),
            _buildActionButtons(
              venta,
              items,
              canPick,
              canVerify,
              canPack,
              canDeliver,
              isCompleted,
              allPicked,
              allVerified,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(
    Venta venta,
    VentaItem item,
    bool canPick,
    bool canVerify,
    bool isCompleted,
  ) {
    // Show different UI based on current state
    if (venta.estado == VentaEstado.SELECCIONANDO) {
      // Picking phase: Show picked checkbox
      return CheckboxListTile(
        title: Text(item.producto.nombre),
        subtitle: Text(
          '${item.cantidad} x ${_getPackagingLabel(item)} @ Bs. ${item.precioVenta.toStringAsFixed(2)}\n'
          'Subtotal: Bs. ${(item.cantidad * item.precioVenta).toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        value: item.picked,
        // Edit on Tap if canPick
        onChanged:
            canPick // Keep checkbox functionality but allow edit via tile tap potentially? No, checkbox takes tap.
            ? (bool? value) {
                // If checkbox is tapped
                setState(() {
                  item.picked = value ?? false;
                });
                Provider.of<VentasProvider>(
                  context,
                  listen: false,
                ).updateItemPicked(item.id!, item.picked);
              }
            : null,
        // Use a trailing IconButton for delete if canPick.
        secondary: canPick
            ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDeleteItem(item),
              )
            : Icon(
                item.picked ? Icons.inventory : Icons.inventory_2_outlined,
                color: item.picked ? Colors.blue : Colors.grey,
              ),
        activeColor: Colors.blue,
        controlAffinity: ListTileControlAffinity.leading,
      );
    } else if (venta.estado == VentaEstado.VERIFICANDO) {
      // Verification phase: Show both picked status and verificado checkbox
      return CheckboxListTile(
        title: Text(item.producto.nombre),
        subtitle: Text(
          '${item.cantidad} x ${_getPackagingLabel(item)} @ Bs. ${item.precioVenta}\n'
          'Recogido: ${item.picked ? "✓" : "✗"}\n'
          'Subtotal: Bs. ${(item.cantidad * item.precioVenta).toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        value: item.verificado,
        onChanged: canVerify
            ? (bool? value) {
                setState(() {
                  item.verificado = value ?? false;
                });
                Provider.of<VentasProvider>(
                  context,
                  listen: false,
                ).updateItemVerificado(item.id!, item.verificado);
              }
            : null,
        secondary: Icon(
          item.verificado ? Icons.check_circle : Icons.check_circle_outline,
          color: item.verificado ? Colors.green : Colors.grey,
        ),
        activeColor: Colors.green,
        controlAffinity: ListTileControlAffinity.leading,
      );
    } else {
      // Other states: Show read-only status
      return ListTile(
        title: Text(item.producto.nombre),
        subtitle: Text(
          '${item.cantidad} x ${item.esPorPaquete ? "Paquete" : "Unidad"} @ Bs. ${item.precioVenta}',
        ),
        trailing: isCompleted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
      );
    }
  }

  Widget _buildActionButtons(
    Venta venta,
    List<VentaItem> items,
    bool canPick,
    bool canVerify,
    bool canPack,
    bool canDeliver,
    bool isCompleted,
    bool allPicked,
    bool allVerified,
  ) {
    if (canPick) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: allPicked ? _sendToVerification : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: Text(
            allPicked
                ? 'Productos Listos para Verificar'
                : 'Marcar todos seleccionados (${items.where((i) => i.picked).length}/${items.length})',
          ),
        ),
      );
    }

    if (canVerify) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: allVerified ? _sendToPacking : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: Text(
            allVerified
                ? 'Ordenar Embalaje'
                : 'Verificar productos (${items.where((i) => i.verificado).length}/${items.length})',
          ),
        ),
      );
    }

    if (canPack) {
      final hasPhotos = venta.fotosEmbalaje.isNotEmpty;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: hasPhotos ? _markPackingComplete : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: hasPhotos ? Colors.purple : Colors.grey,
          ),
          child: Text(
            hasPhotos
                ? 'Embalaje Completo'
                : 'Tome al menos una foto del embalaje',
          ),
        ),
      );
    }

    if (canDeliver) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _confirmDelivery,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Confirmar Entrega al Cliente'),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _getPackagingLabel(VentaItem item) {
    if (item.esSurtido) return 'Paq. Surtido';
    return item.esPorPaquete ? 'Paquete' : 'Unidad';
  }

  String _getEstadoDisplayName(VentaEstado estado) {
    switch (estado) {
      case VentaEstado.SELECCIONANDO:
        return 'Seleccionando';
      case VentaEstado.VERIFICANDO:
        return 'Verificando';
      case VentaEstado.EMBALANDO:
        return 'Embalando';
      case VentaEstado.LISTA_ENTREGA:
        return 'Lista Entrega';
      case VentaEstado.COMPLETADA:
        return 'Completada';
      case VentaEstado.CANCELADA:
        return 'Cancelada';
    }
  }

  Color _getEstadoColor(VentaEstado estado) {
    switch (estado) {
      case VentaEstado.SELECCIONANDO:
        return Colors.blue;
      case VentaEstado.VERIFICANDO:
        return Colors.orange;
      case VentaEstado.EMBALANDO:
        return Colors.purple;
      case VentaEstado.LISTA_ENTREGA:
        return Colors.lightGreen;
      case VentaEstado.COMPLETADA:
        return Colors.green;
      case VentaEstado.CANCELADA:
        return Colors.red;
    }
  }

  Widget _buildPackingPhotosSection(Venta venta, bool canEdit, bool isAdmin) {
    // Solo mostrar si ya pasó de VERIFICANDO
    bool showSection =
        venta.estado != VentaEstado.SELECCIONANDO &&
        venta.estado != VentaEstado.VERIFICANDO;

    if (!showSection) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Fotos del Embalaje:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.add_a_photo, color: Colors.purple),
                onPressed: () => _pickPackingImage(venta.id!),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (venta.fotosEmbalaje.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay fotos del embalaje.',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: venta.fotosEmbalaje.length,
              itemBuilder: (context, index) {
                final path = venta.fotosEmbalaje[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FullScreenImageScreen(imagePath: path),
                            ),
                          );
                        },
                        child: Hero(
                          tag: path,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(path),
                              width: 100,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      if (canEdit)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.red,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  _removePackingImage(venta.id!, path),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _pickPackingImage(int ventaId) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (image != null) {
        if (!mounted) return;
        await Provider.of<VentasProvider>(
          context,
          listen: false,
        ).addPackingPhoto(ventaId, image.path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al tomar foto: $e')));
    }
  }

  Future<void> _removePackingImage(int ventaId, String path) async {
    final provider = Provider.of<VentasProvider>(context, listen: false);
    await provider.removePackingPhoto(ventaId, path);
  }
}

class FullScreenImageScreen extends StatelessWidget {
  final String imagePath;

  const FullScreenImageScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(File(imagePath)),
        ),
      ),
    );
  }
}
