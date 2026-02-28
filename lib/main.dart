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
import 'package:google_fonts/google_fonts.dart';
import 'excel_service.dart';

// --- SISTEMA DE DISEÑO (BOOKING STYLE) ---

class AppColors {
  static const Color primary = Color(0xFF1E3A8A); // Navy Blue
  static const Color secondary = Color(0xFF3B82F6); // Bright Blue
  static const Color accent = Color(0xFFCA8A04); // Gold / Ochre
  static const Color background = Color(0xFFF8FAFC); // Off-white / Blue tint
  static const Color surface = Colors.white;
  static const Color textBody = Color(0xFF1E293B); // Slate 800
  static const Color textMuted = Color(0xFF64748B); // Slate 500

  // Status Colors
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // Helper para Notificaciones Modernas
  static void showNotification(
    BuildContext context,
    String message, {
    Color color = AppColors.primary,
    IconData? icon,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon ?? Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.openSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

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
  String get searchQuery => _searchQuery;
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
      AppColors.showNotification(
        context,
        'Por favor ingrese usuario y contraseña',
        color: AppColors.warning,
        icon: Icons.warning_amber_rounded,
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else {
      AppColors.showNotification(
        context,
        'Usuario o contraseña incorrectos',
        color: AppColors.error,
        icon: Icons.error_outline_rounded,
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
      AppColors.showNotification(
        context,
        'Error de autenticación biométrica o no configurada',
        color: AppColors.error,
        icon: Icons.fingerprint_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Fondo decorativo superior (estilo Booking)
          Container(
            height: MediaQuery.of(context).size.height * 0.4,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 40.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Marca / Logo
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        size: 60,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Inventas',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'Gestión de Inventario y Ventas',
                      style: GoogleFonts.openSans(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Card de Login
                    Card(
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Logo / Header Estilo Booking
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.inventory_2_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Inventas Pro',
                                style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              Text(
                                'Gestión de Inventario y Ventas',
                                style: GoogleFonts.openSans(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 48),
                              // Formulario
                              _buildTextField(
                                controller: _usernameController,
                                label: 'Usuario',
                                icon: Icons.person_outline_rounded,
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _passwordController,
                                label: 'Contraseña',
                                icon: Icons.lock_outline_rounded,
                                obscureText: true,
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          'INICIAR SESIÓN',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextButton(
                                onPressed: () {},
                                child: Text(
                                  '¿Olvidaste tu contraseña?',
                                  style: GoogleFonts.openSans(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Biometría
                              if (!_isLoading)
                                FutureBuilder<bool>(
                                  future: Provider.of<UserProvider>(
                                    context,
                                    listen: false,
                                  ).canUseBiometrics(),
                                  builder: (context, snapshot) {
                                    if (snapshot.data == true) {
                                      return Column(
                                        children: [
                                          Text(
                                            'O ingresa con tu huella',
                                            style: GoogleFonts.openSans(
                                              fontSize: 13,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          InkWell(
                                            onTap: _loginBiometric,
                                            borderRadius: BorderRadius.circular(
                                              50,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.grey.shade200,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.05),
                                                    blurRadius: 10,
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.fingerprint_rounded,
                                                size: 40,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.grey.shade50,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: GoogleFonts.openSans(color: AppColors.textMuted),
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
            icon: Icon(Icons.search_rounded),
            activeIcon: Icon(Icons.search_rounded),
            label: 'Explorar',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Ventas',
          ),
          if (userProvider.isAdmin)
            const BottomNavigationBarItem(
              icon: Icon(Icons.assignment_turned_in_outlined),
              activeIcon: Icon(Icons.assignment_turned_in),
              label: 'Aprobaciones',
            ),
          if (userProvider.isAdmin)
            const BottomNavigationBarItem(
              icon: Icon(Icons.manage_accounts_outlined),
              activeIcon: Icon(Icons.manage_accounts),
              label: 'Usuarios',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Inventas',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
            actions: [
              IconButton(
                onPressed: () {
                  AppColors.showNotification(
                    context,
                    'No hay notificaciones nuevas',
                  );
                },
                icon: const Badge(
                  backgroundColor: AppColors.error,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.primary,
                  ),
                ),
                tooltip: 'Notificaciones',
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_circle_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      userProvider.currentUser?.username ?? '',
                      style: GoogleFonts.openSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: Colors.grey.shade200),
            ),
          ),
          body: IndexedStack(index: _selectedIndex, children: screens),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              items: navItems,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              // Los colores ya están definidos en el tema global
            ),
          ),
        );
      },
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, VentasProvider>(
      builder: (context, userProvider, ventasProvider, child) {
        final user = userProvider.currentUser;
        if (user == null) return const SizedBox();

        final accountAge = DateTime.now().difference(user.createdAt).inDays;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: FutureBuilder<int>(
            future: ventasProvider.getUserSalesCount(user.id!),
            builder: (context, snapshot) {
              final salesCount = snapshot.data ?? 0;

              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 280,
                    pinned: true,
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  Color(0xFF1E3A8A),
                                ], // Darker blue
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -50,
                            top: -20,
                            child: Icon(
                              Icons.manage_accounts_rounded,
                              size: 200,
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 40),
                              Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 56,
                                      backgroundColor: Colors.white,
                                      backgroundImage: user.photoPath.isNotEmpty
                                          ? FileImage(File(user.photoPath))
                                          : null,
                                      child: user.photoPath.isEmpty
                                          ? Text(
                                              user.username
                                                  .substring(0, 1)
                                                  .toUpperCase(),
                                              style: GoogleFonts.poppins(
                                                fontSize: 48,
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => _pickProfilePhoto(
                                        context,
                                        userProvider,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors
                                              .warning, // Highlight color
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.1,
                                              ),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                user.nombre ?? user.username,
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _getRoleDisplayName(user.role).toUpperCase(),
                                  style: GoogleFonts.openSans(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (user.telefono != null &&
                              user.telefono!.isNotEmpty) ...[
                            _buildSectionHeader('Contacto'),
                            _buildInfoCard(
                              icon: Icons.phone_android_rounded,
                              title: 'Teléfono / WhatsApp',
                              subtitle: user.telefono!,
                            ),
                            const SizedBox(height: 24),
                          ],
                          _buildSectionHeader('Estadísticas'),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  value: salesCount.toString(),
                                  label: 'Ventas\nGeneradas',
                                  icon: Icons.receipt_long_rounded,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildStatCard(
                                  value: accountAge.toString(),
                                  label: 'Días\nRegistrado',
                                  icon: Icons.calendar_today_rounded,
                                  color: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          _buildSectionHeader('Seguridad'),
                          FutureBuilder<bool>(
                            future: userProvider.canUseBiometrics(),
                            builder: (context, snapshot) {
                              final canUseBio = snapshot.data ?? false;
                              return _buildSettingsCard(
                                icon: Icons.fingerprint_rounded,
                                title: 'Ingreso con Huella',
                                subtitle: canUseBio
                                    ? 'Inicia sesión rápidamente con tu biometría'
                                    : 'No disponible en este dispositivo',
                                trailing: canUseBio
                                    ? Switch.adaptive(
                                        activeColor: AppColors.primary,
                                        value: user.biometricEnabled,
                                        onChanged: (bool value) async {
                                          if (value) {
                                            _showPasswordConfirmDialog(
                                              context,
                                              userProvider,
                                            );
                                          } else {
                                            await userProvider
                                                .updateBiometricPreference(
                                                  false,
                                                  '',
                                                );
                                          }
                                        },
                                      )
                                    : const Icon(
                                        Icons.block_rounded,
                                        color: Colors.grey,
                                      ),
                              );
                            },
                          ),
                          const SizedBox(height: 48),
                          ElevatedButton.icon(
                            onPressed: () {
                              userProvider.logout();
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('CERRAR SESIÓN'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 56),
                              backgroundColor: AppColors.error.withOpacity(0.1),
                              foregroundColor: AppColors.error,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: AppColors.error.withOpacity(0.5),
                                ),
                              ),
                              textStyle: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.openSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.openSans(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: trailing,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirmar Contraseña',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Para habilitar el ingreso con huella, ingrese su contraseña actual para guardarla de forma segura.',
              style: GoogleFonts.openSans(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                  SnackBar(
                    content: const Text('Contraseña incorrecta'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
                  initialValue: selectedRole,
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
    // Definimos los esquemas de texto usando Google Fonts
    final textTheme = GoogleFonts.openSansTextTheme(Theme.of(context).textTheme)
        .copyWith(
          displayLarge: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          displayMedium: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          displaySmall: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          headlineLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          headlineMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          headlineSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          titleLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          titleSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventas Booking',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          background: AppColors.background,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.primary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.poppins(
            color: AppColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: AppColors.primary),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style:
              ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                elevation: 0,
              ).copyWith(
                overlayColor: WidgetStateProperty.all(
                  Colors.white.withOpacity(0.1),
                ),
              ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          filled: true,
          fillColor: AppColors.surface,
          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          elevation: 20,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: TextStyle(fontSize: 12),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Barra de búsqueda con estilo Booking
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => Provider.of<ProductProvider>(
                      context,
                      listen: false,
                    ).search(value),
                    decoration: InputDecoration(
                      hintText: '¿Qué producto buscas?',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botones de acción rápida (Import/Export)
                _buildActionIconButton(
                  context,
                  icon: Icons.file_download_outlined,
                  onPressed: () {
                    final products = Provider.of<ProductProvider>(
                      context,
                      listen: false,
                    ).products;
                    ExcelService.exportProducts(products);
                  },
                ),
                const SizedBox(width: 8),
                _buildActionIconButton(
                  context,
                  icon: Icons.file_upload_outlined,
                  onPressed: () async {
                    final newProducts = await ExcelService.importProducts();
                    if (newProducts != null && newProducts.isNotEmpty) {
                      _showImportConfirmation(context, newProducts);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ProductProvider>(
              builder: (context, provider, child) {
                if (provider.products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: AppColors.textMuted.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay productos que coincidan',
                          style: GoogleFonts.openSans(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: provider.products.length,
                  itemBuilder: (context, index) {
                    final product = provider.products[index];
                    return _ProductListingCard(product: product);
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddProductScreen(),
                ),
              ),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(
                'Nuevo Producto',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              backgroundColor: AppColors.primary,
              elevation: 4,
            )
          : null,
    );
  }

  Widget _buildActionIconButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.primary, size: 22),
        onPressed: onPressed,
      ),
    );
  }

  void _showImportConfirmation(
    BuildContext context,
    List<Product> newProducts,
  ) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirmar Importación',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // ignore: use_build_context_synchronously
      _executeImport(context, newProducts);
    }
  }

  void _executeImport(BuildContext context, List<Product> newProducts) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await Provider.of<ProductProvider>(
        context,
        listen: false,
      ).addProducts(newProducts);
      // ignore: use_build_context_synchronously
      Navigator.pop(context); // Cerrar loader
      // ignore: use_build_context_synchronously
      AppColors.showNotification(
        context,
        '${newProducts.length} productos importados con éxito',
        color: AppColors.success,
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      // ignore: use_build_context_synchronously
      Navigator.pop(context); // Cerrar loader
      // ignore: use_build_context_synchronously
      AppColors.showNotification(
        context,
        'Error de Importación: $e',
        color: AppColors.error,
        icon: Icons.error_outline,
      );
    }
  }
}

class _ProductListingCard extends StatelessWidget {
  final Product product;
  const _ProductListingCard({required this.product});

  @override
  Widget build(BuildContext context) {
    bool lowStock = product.stock < (product.unidadesPorPaquete * 3);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showProductDetailModal(context, product),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen principal (más grande)
                Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 140,
                      decoration: BoxDecoration(color: Colors.grey.shade100),
                      child: product.fotoPaths.isNotEmpty
                          ? Image.file(
                              File(product.fotoPaths.first),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildErrorIcon(),
                            )
                          : _buildErrorIcon(),
                    ),
                    if (lowStock)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'STOCK BAJO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // Detalles
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product.nombre,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (Provider.of<UserProvider>(
                              context,
                              listen: false,
                            ).canManageInventory)
                              _buildMenu(context),
                          ],
                        ),
                        Text(
                          product.marca,
                          style: GoogleFonts.openSans(
                            fontSize: 14,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Ubicación
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              product.ubicacion,
                              style: GoogleFonts.openSans(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Disponibilidad y Precio
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Disponibilidad:',
                                  style: GoogleFonts.openSans(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  '${(product.stock ~/ product.unidadesPorPaquete)} Paq + ${(product.stock % product.unidadesPorPaquete)} Uni',
                                  style: GoogleFonts.openSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: lowStock
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Desde',
                                  style: GoogleFonts.openSans(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  'Bs. ${product.precioUnidad.toStringAsFixed(2)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorIcon() {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey,
        size: 40,
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
      onSelected: (value) {
        if (value == 'edit') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditProductScreen(product: product),
            ),
          );
        } else if (value == 'delete') {
          _showDeleteConfirmationDialog(context, product);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined, color: AppColors.primary),
            title: Text('Editar'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded, color: AppColors.error),
            title: Text('Eliminar'),
          ),
        ),
      ],
    );
  }
}

void _showProductDetailModal(BuildContext context, Product product) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ProductDetailSheet(product: product),
  );
}

void _showDeleteConfirmationDialog(BuildContext context, Product product) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Confirmar Eliminación',
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: Text(
        '¿Estás seguro de que quieres eliminar "${product.nombre}"? esta acción no se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Provider.of<ProductProvider>(
              context,
              listen: false,
            ).deleteProduct(product.id!);
            Navigator.pop(context);
            AppColors.showNotification(
              context,
              'Producto eliminado',
              color: AppColors.error,
              icon: Icons.delete_outline,
            );
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
}

class _ProductDetailSheet extends StatefulWidget {
  final Product product;
  const _ProductDetailSheet({required this.product});

  @override
  State<_ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<_ProductDetailSheet> {
  int _currentCarouselIndex = 0;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // Header con imagen (Estilo Hotel)
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  leading: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withOpacity(0.3),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      children: [
                        if (product.fotoPaths.isNotEmpty)
                          CarouselSlider(
                            options: CarouselOptions(
                              height: 350,
                              viewportFraction: 1.0,
                              onPageChanged: (index, _) =>
                                  setState(() => _currentCarouselIndex = index),
                            ),
                            items: product.fotoPaths
                                .map(
                                  (path) => GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FullScreenImageScreen(
                                          imagePath: path,
                                        ),
                                      ),
                                    ),
                                    child: Image.file(
                                      File(path),
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                                .toList(),
                          )
                        else
                          Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 80,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        // Indicadores de carrusel
                        if (product.fotoPaths.length > 1)
                          Positioned(
                            bottom: 20,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: product.fotoPaths.asMap().entries.map((
                                entry,
                              ) {
                                return Container(
                                  width: 8.0,
                                  height: 8.0,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(
                                      _currentCarouselIndex == entry.key
                                          ? 0.9
                                          : 0.4,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge de Categoría/Ubicación
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            product.marca.toUpperCase(),
                            style: GoogleFonts.openSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          product.nombre,
                          style: GoogleFonts.poppins(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              product.ubicacion,
                              style: GoogleFonts.openSans(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(),
                        ),

                        // Información de Stock
                        _buildSectionTitle(
                          'Disponibilidad de Habitaciones (Stock)',
                        ),
                        const SizedBox(height: 16),
                        _buildInfoTile(
                          Icons.inventory_2_outlined,
                          'Stock Total en Sistema',
                          '${(product.stock ~/ product.unidadesPorPaquete)} Paquetes cerrados',
                          value2:
                              '${(product.stock % product.unidadesPorPaquete)} Unidades sueltas',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoTile(
                          Icons.layers_outlined,
                          'Información de Empaque',
                          'Cada unidad contiene ${product.unidadesPorPaquete} items',
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(),
                        ),

                        // Precios (Estilo Reserva)
                        _buildSectionTitle('Precios y Tarifas'),
                        const SizedBox(height: 16),
                        _buildPriceCard(
                          'Precio por Paquete',
                          product.precioPaquete,
                          subtitle: 'Ideal para ventas mayoristas',
                        ),
                        if (product.precioPaqueteSurtido > 0)
                          _buildPriceCard(
                            'Precio Paquete Surtido',
                            product.precioPaqueteSurtido,
                            subtitle: 'Paquetes con variedad',
                          ),
                        _buildPriceCard(
                          'Precio por Unidad',
                          product.precioUnidad,
                          subtitle: 'Venta al detalle',
                          isLast: true,
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(),
                        ),

                        // Descripción
                        if (product.descripcion.isNotEmpty) ...[
                          _buildSectionTitle('Sobre este producto'),
                          const SizedBox(height: 12),
                          Text(
                            product.descripcion,
                            style: GoogleFonts.openSans(
                              fontSize: 15,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(),
                          ),
                        ],

                        // Código QR
                        _buildSectionTitle('Identificación Digital (QR)'),
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              if (product.qrCode != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: QrImageView(
                                    data: product.qrCode!,
                                    version: QrVersions.auto,
                                    size: 160.0,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  product.qrCode!,
                                  style: GoogleFonts.openSans(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ] else
                                Text(
                                  'Sin código QR generado',
                                  style: GoogleFonts.openSans(
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Botón de acción inferior
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Desde',
                        style: GoogleFonts.openSans(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        'Bs. ${product.precioUnidad.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Aquí podrías agregar a la venta si existiera un carrito
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'RESERVAR / VENDER',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String title,
    String value1, {
    String? value2,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.openSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                value1,
                style: GoogleFonts.openSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              if (value2 != null)
                Text(
                  value2,
                  style: GoogleFonts.openSans(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceCard(
    String title,
    double price, {
    required String subtitle,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : Colors.grey.shade100,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.openSans(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Bs. ${price.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.success,
            ),
          ),
        ],
      ),
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
    final isAdding = this is _AddProductScreenState;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isAdding ? 'Registrar Propiedad' : 'Editar Información',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader(
                Icons.info_outline_rounded,
                'Información General',
              ),
              const SizedBox(height: 16),
              _buildModernField(
                controller: _nombreController,
                label: 'Nombre del Producto',
                icon: Icons.abc_rounded,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa un nombre' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildModernField(
                      controller: _marcaController,
                      label: 'Categoría / Marca',
                      icon: Icons.label_important_outline_rounded,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Campo obligatorio' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModernField(
                      controller: _ubicacionController,
                      label: 'Ubicación',
                      icon: Icons.place_outlined,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Campo obligatorio' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              _buildSectionHeader(
                Icons.inventory_2_outlined,
                'Gestión de Stock',
              ),
              const SizedBox(height: 16),
              _buildModernField(
                controller: _unidadesController,
                label: 'Unidades por Paquete',
                icon: Icons.layers_outlined,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa unidades' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildModernField(
                      controller: _paquetesStockController,
                      label: 'Stock (Paquetes)',
                      icon: Icons.view_headline_rounded,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModernField(
                      controller: _unidadesSueltasStockController,
                      label: 'Sueltos',
                      icon: Icons.more_horiz_rounded,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              _buildSectionHeader(Icons.payments_outlined, 'Tarifas y Precios'),
              const SizedBox(height: 16),
              _buildModernField(
                controller: _precioPaqueteController,
                label: 'Precio por Paquete (Bs.)',
                icon: Icons.sell_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa un precio' : null,
              ),
              const SizedBox(height: 16),
              _buildModernField(
                controller: _precioPaqueteSurtidoController,
                label: 'Precio Paquete Surtido (Opcional)',
                icon: Icons.account_balance_wallet_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              _buildModernField(
                controller: _precioUnidadController,
                label: 'Precio por Unidad (Bs.)',
                icon: Icons.monetization_on_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa un precio' : null,
              ),
              const SizedBox(height: 32),

              _buildSectionHeader(
                Icons.description_outlined,
                'Descripción Detallada',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descripcionController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Cuéntanos un poco más sobre este producto...',
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              _buildSectionHeader(
                Icons.photo_camera_back_outlined,
                'Galería de Fotos',
              ),
              const SizedBox(height: 16),
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: (_imageFiles.isEmpty && _existingImagePaths.isEmpty)
                    ? Center(
                        child: Text(
                          'Ninguna foto seleccionada',
                          style: GoogleFonts.openSans(
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(12),
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
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Cámara'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: saveProduct,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: AppColors.primary,
                ),
                child: Text(
                  isAdding ? 'PUBLICAR PRODUCTO' : 'GUARDAR CAMBIOS',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.openSans(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          size: 20,
          color: AppColors.primary.withOpacity(0.5),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(File imageFile, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: Image.file(
              imageFile,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
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
      backgroundColor: AppColors.background,
      body: Consumer<VentasProvider>(
        builder: (context, provider, child) {
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );
          final displayedVentas = userProvider.canViewAllSales
              ? provider.ventas
              : provider.getVentasByUser(userProvider.currentUser!.id!);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 140.0,
                floating: true,
                pinned: true,
                backgroundColor: AppColors.primary,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    'Mis Reservas',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: AppColors.primary),
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 150,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.filter_list_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
              if (displayedVentas.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.event_busy_rounded,
                            size: 64,
                            color: AppColors.textMuted.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No hay listas o reservas registradas.',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tus futuras ventas aparecerán aquí.',
                          style: GoogleFonts.openSans(
                            color: AppColors.textMuted.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final venta = displayedVentas[index];
                      return _ReservationCard(venta: venta);
                    }, childCount: displayedVentas.length),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateSaleScreen()),
        ),
        label: Text(
          'NUEVA RESERVA',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        icon: const Icon(Icons.add_business_rounded),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
      ),
    );
  }

  Widget _buildStatusBadge(VentaEstado estado) {
    Color color;
    String text = estado.name.toUpperCase();

    switch (estado) {
      case VentaEstado.COMPLETADA:
        color = AppColors.success;
        break;
      case VentaEstado.CANCELADA:
        color = AppColors.error;
        break;
      case VentaEstado.SELECCIONANDO:
        color = Colors.blue;
        text = "BORRADOR";
        break;
      case VentaEstado.VERIFICANDO:
        color = Colors.orange;
        break;
      case VentaEstado.EMBALANDO:
        color = Colors.teal;
        break;
      case VentaEstado.LISTA_ENTREGA:
        color = Colors.purple;
        text = "LISTO";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProgressBar(Venta venta, Color color) {
    double progress = 0;
    String label = "";

    if (venta.estado == VentaEstado.SELECCIONANDO) {
      progress = venta.items.isEmpty
          ? 0
          : venta.items.where((i) => i.picked).length / venta.items.length;
      label = "Selección de ítems";
    } else if (venta.estado == VentaEstado.VERIFICANDO) {
      progress = venta.items.isEmpty
          ? 0
          : venta.items.where((i) => i.verificado).length / venta.items.length;
      label = "Verificación en curso";
    } else if (venta.estado == VentaEstado.EMBALANDO) {
      progress = 0.8;
      label = "Embalando pedido";
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.openSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final Venta venta;
  const _ReservationCard({required this.venta});

  @override
  Widget build(BuildContext context) {
    final isCompleted = venta.estado == VentaEstado.COMPLETADA;
    final isCancelled = venta.estado == VentaEstado.CANCELADA;

    Color statusColor;
    switch (venta.estado) {
      case VentaEstado.COMPLETADA:
        statusColor = AppColors.success;
        break;
      case VentaEstado.CANCELADA:
        statusColor = AppColors.error;
        break;
      case VentaEstado.SELECCIONANDO:
        statusColor = Colors.blue;
        break;
      case VentaEstado.VERIFICANDO:
        statusColor = Colors.orange;
        break;
      case VentaEstado.EMBALANDO:
        statusColor = Colors.teal;
        break;
      case VentaEstado.LISTA_ENTREGA:
        statusColor = Colors.purple;
        break;
      default:
        statusColor = Colors.grey;
    }

    final parent = context.findAncestorWidgetOfExactType<SalesListScreen>();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SaleDetailScreen(venta: venta)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header del Card
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  venta.nombreCliente,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: AppColors.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (parent != null)
                                parent._buildStatusBadge(venta.estado),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 13,
                                color: AppColors.textMuted.withOpacity(0.6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat(
                                  'dd MMM yyyy • HH:mm',
                                ).format(venta.fecha),
                                style: GoogleFonts.openSans(
                                  fontSize: 12,
                                  color: AppColors.textMuted.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Divisor sutil
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  height: 1,
                  color: Colors.grey.shade100,
                  thickness: 1,
                ),
              ),

              // Info de Precio / Adiantos
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IMPORTANTE TOTAL',
                          style: GoogleFonts.openSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMuted.withOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bs. ${venta.total.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: isCancelled
                                ? AppColors.textMuted
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (venta.adelanto > 0)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SALDO PENDIENTE',
                              style: GoogleFonts.openSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.error,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Bs. ${(venta.total - venta.adelanto).toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Barra de Progreso (si no está terminada)
              if (!isCompleted && !isCancelled && parent != null)
                parent._buildProgressBar(venta, statusColor),

              // Footer: Vendedor / Acción
              Container(
                padding: const EdgeInsets.all(14),
                color: AppColors.primary.withOpacity(0.03),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_pin_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.openSans(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                          children: [
                            const TextSpan(text: 'Gestionado por: '),
                            TextSpan(
                              text: venta.nombreVendedor ?? "Desconocido",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  String? _metodoPagoAdelanto;

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
    _adelantoController.removeListener(_saveDraft);
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
      'metodo_pago': _metodoPagoAdelanto,
      'items': _cart
          .map(
            (item) => {
              'productId': item.producto.id,
              'quantity': item.cantidad,
              'isPackage': item.esPorPaquete,
              'isSurtido': item.esSurtido,
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
        if (mounted) {
          _nombreClienteController.text = draftData['nombre'] ?? '';
          _telefonoClienteController.text = draftData['telefono'] ?? '';
          _adelantoController.text = draftData['adelanto'] ?? '';
          _metodoPagoAdelanto = draftData['metodo_pago'];
        }
        final List<dynamic> itemsData = draftData['items'] ?? [];

        final productProvider = Provider.of<ProductProvider>(
          context,
          listen: false,
        );
        if (productProvider.products.isEmpty) {
          await productProvider.fetchProducts();
        }

        List<VentaItem> restoredItems = [];
        for (var itemData in itemsData) {
          final productId = itemData['productId'];
          final product = productProvider.getProductById(productId);
          if (product != null) {
            final quantity = itemData['quantity'];
            final isPackage = itemData['isPackage'] ?? false;
            final isSurtido = itemData['isSurtido'] ?? false;

            double price = product.precioUnidad;
            if (isSurtido) {
              price = product.precioPaqueteSurtido;
            } else if (isPackage)
              price = product.precioPaquete;

            restoredItems.add(
              VentaItem(
                ventaId: 0,
                producto: product,
                cantidad: quantity,
                precioVenta: price,
                esPorPaquete: isPackage,
                esSurtido: isSurtido,
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
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
        _metodoPagoAdelanto = null;
        _cart.clear();
        _calculateTotal();
      });
    }
  }

  void _calculateTotal() {
    _total = _cart.fold(
      0.0,
      (sum, item) => sum + (item.cantidad * item.precioVenta),
    );
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
      AppColors.showNotification(
        context,
        'Stock insuficiente para esta cantidad',
        color: AppColors.error,
        icon: Icons.warning_amber_rounded,
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

  Future<void> _saveSale() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cart.isEmpty) {
      AppColors.showNotification(
        context,
        'La lista está vacía',
        color: AppColors.warning,
      );
      return;
    }

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final ventasProvider = Provider.of<VentasProvider>(context, listen: false);

    final newVenta = Venta(
      id: 0,
      userId: userProvider.currentUser!.id!,
      nombreCliente: _nombreClienteController.text,
      telefonoCliente: _telefonoClienteController.text,
      fecha: DateTime.now(),
      total: _total,
      adelanto: double.tryParse(_adelantoController.text) ?? 0.0,
      metodoPagoAdelanto: _metodoPagoAdelanto ?? 'Efectivo',
      estado: VentaEstado.SELECCIONANDO,
      nombreVendedor: userProvider.currentUser!.username,
      items: _cart,
      fotosEmbalaje: [],
    );

    try {
      await ventasProvider.addVenta(newVenta);
      await _clearDraft();
      if (!mounted) return;
      Navigator.pop(context);
      AppColors.showNotification(
        context,
        'Reserva registrada con éxito',
        color: AppColors.success,
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      AppColors.showNotification(
        context,
        'Error al guardar reserva: $e',
        color: AppColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Nueva Reserva',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.delete_sweep_outlined,
              color: AppColors.error,
            ),
            onPressed: _cart.isEmpty && _nombreClienteController.text.isEmpty
                ? null
                : _discardDraft,
            tooltip: 'Vaciar Todo',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSectionHeader(
              Icons.person_outline_rounded,
              'Detalles del Cliente',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildCheckoutField(
                        controller: _nombreClienteController,
                        label: 'Nombre completo del cliente',
                        icon: Icons.badge_outlined,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildCheckoutField(
                        controller: _telefonoClienteController,
                        label: 'Teléfono / WhatsApp',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            _buildSectionHeader(
              Icons.shopping_bag_outlined,
              'Ítems en Reserva',
            ),
            if (_cart.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_shopping_cart_rounded,
                      size: 48,
                      color: AppColors.textMuted.withOpacity(0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'La reserva está vacía',
                      style: GoogleFonts.openSans(color: AppColors.textMuted),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _cart.length,
                  itemBuilder: (context, index) {
                    final item = _cart[index];
                    return _buildCartItem(item, index);
                  },
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton.icon(
                onPressed: () => _showAddProductDialog(),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('AÑADIR PRODUCTO'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            _buildSectionHeader(
              Icons.account_balance_wallet_outlined,
              'Garantía / Adelanto',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildCheckoutField(
                      controller: _adelantoController,
                      label: 'Monto del adelanto (Bs.)',
                      icon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _metodoPagoAdelanto,
                      decoration: InputDecoration(
                        labelText: 'Método de Pago',
                        prefixIcon: const Icon(
                          Icons.credit_card_rounded,
                          color: AppColors.primary,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      items: ['Efectivo', 'Transferencia', 'QR']
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() {
                        _metodoPagoAdelanto = val;
                        _saveDraft();
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomSheet: _buildBottomCheckoutPanel(),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primary.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          size: 20,
          color: AppColors.primary.withOpacity(0.5),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildCartItem(VentaItem item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.producto.fotoPaths.isNotEmpty
                ? Image.file(
                    File(item.producto.fotoPaths.first),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.inventory_2_outlined),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.producto.nombre,
                  style: GoogleFonts.openSans(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${item.cantidad} x Bs. ${item.precioVenta.toStringAsFixed(2)} ${item.esSurtido ? "(Surt.)" : (item.esPorPaquete ? "(Paq.)" : "(Uni.)")}',
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline_rounded,
              color: AppColors.error,
            ),
            onPressed: () => _removeFromCart(index),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCheckoutPanel() {
    double adelantoVal = double.tryParse(_adelantoController.text) ?? 0.0;
    double saldo = _total - adelantoVal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL A PAGAR',
                      style: GoogleFonts.openSans(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      'Bs. ${_total.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                if (adelantoVal > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'SALDO',
                        style: GoogleFonts.openSans(
                          fontSize: 12,
                          color: AppColors.error,
                        ),
                      ),
                      Text(
                        'Bs. ${saldo.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _cart.isEmpty ? null : () => _saveSale(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'CONFIRMAR RESERVA',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProductDialog() {
    final productProvider = Provider.of<ProductProvider>(
      context,
      listen: false,
    );
    productProvider.search('');
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Seleccionar Ítem',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    setDialogState(() {
                      productProvider.search(v);
                    });
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Consumer<ProductProvider>(
                    builder: (context, provider, _) {
                      return ListView.builder(
                        itemCount: provider.products.length,
                        itemBuilder: (context, i) {
                          final p = provider.products[i];
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.grey.shade50,
                            child: ListTile(
                              title: Text(
                                p.nombre,
                                style: GoogleFonts.openSans(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Stock: ${p.stock} | Uni: Bs. ${p.precioUnidad}',
                                style: GoogleFonts.openSans(fontSize: 12),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _showQuantityDialog(p);
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
                productProvider.search('');
                Navigator.pop(context);
              },
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuantityDialog(Product product) {
    final qtyController = TextEditingController(text: '1');
    String saleType = 'unidad';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setQtyState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Configurar Reserva',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(product.nombre, style: GoogleFonts.openSans(fontSize: 16)),
              const SizedBox(height: 20),
              TextField(
                controller: qtyController,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: saleType,
                decoration: InputDecoration(
                  labelText: 'Tipo de Venta',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'unidad',
                    child: Text('Por Unidad'),
                  ),
                  const DropdownMenuItem(
                    value: 'paquete',
                    child: Text('Por Paquete'),
                  ),
                  if (product.precioPaqueteSurtido > 0)
                    const DropdownMenuItem(
                      value: 'surtido',
                      child: Text('Paquete Surtido'),
                    ),
                ],
                onChanged: (v) => setQtyState(() => saleType = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final quantity = int.tryParse(qtyController.text) ?? 0;
                if (quantity > 0) {
                  _addToCart(
                    product,
                    quantity,
                    isPackage: saleType == 'paquete',
                    isSurtido: saleType == 'surtido',
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Añadir'),
            ),
          ],
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
    AppColors.showNotification(
      context,
      'Productos enviados a verificación.',
      color: Colors.blue,
      icon: Icons.fact_check_rounded,
    );
    Navigator.pop(context);
  }

  Future<void> _sendToPacking() async {
    await Provider.of<VentasProvider>(
      context,
      listen: false,
    ).updateVentaStatus(widget.venta.id!, VentaEstado.EMBALANDO);
    AppColors.showNotification(
      context,
      'Productos verificados. Proceder a embalar.',
      color: Colors.orange,
      icon: Icons.inventory_2_rounded,
    );
    Navigator.pop(context);
  }

  Future<void> _markPackingComplete() async {
    await Provider.of<VentasProvider>(
      context,
      listen: false,
    ).updateVentaStatus(widget.venta.id!, VentaEstado.LISTA_ENTREGA);
    AppColors.showNotification(
      context,
      'Embalaje completo. Lista para entregar.',
      color: Colors.purple,
      icon: Icons.local_shipping_rounded,
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
    AppColors.showNotification(
      context,
      'Venta completada y stock actualizado.',
      color: AppColors.success,
      icon: Icons.verified_rounded,
    );
    Navigator.pop(context);
  }

  Future<void> _deleteVenta() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Reserva?'),
        content: const Text(
          'Esta acción cancelará todo y no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
      AppColors.showNotification(
        context,
        'Reserva eliminada correctamente',
        color: AppColors.error,
      );
    }
  }

  void _showProductSelectorDialog() {
    final productProvider = Provider.of<ProductProvider>(
      context,
      listen: false,
    );
    productProvider.search('');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Agregar Productos',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  onChanged: (value) => productProvider.search(value),
                  decoration: InputDecoration(
                    hintText: 'Buscar productos...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Consumer<ProductProvider>(
                  builder: (context, provider, child) {
                    if (provider.products.isEmpty) {
                      return const Center(child: Text('Sin resultados.'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: provider.products.length,
                      itemBuilder: (context, index) {
                        final product = provider.products[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade100),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: product.fotoPaths.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(product.fotoPaths[0]),
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(Icons.inventory_2_outlined),
                            ),
                            title: Text(
                              product.nombre,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Bs. ${product.precioUnidad} / unid.',
                            ),
                            onTap: () {
                              Navigator.pop(context);
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                product.nombre,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: quantityController,
                    decoration: InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Formato de venta:',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: saleType,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
                  const SizedBox(height: 16),
                  _buildPriceHint(product, saleType),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
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
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Añadir'),
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
        detail = '${product.unidadesPorPaquete} items';
        break;
      case 'surtido':
        price = product.precioPaqueteSurtido;
        detail = '${product.unidadesPorPaquete} items (Surtido)';
        break;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Precio: Bs. ${price.toStringAsFixed(2)} ($detail)',
              style: GoogleFonts.openSans(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteItem(VentaItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Quitar ${item.producto.nombre}?'),
        content: const Text('El producto será eliminado de esta reserva.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mantener'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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

      AppColors.showNotification(
        context,
        'Producto eliminado.',
        color: AppColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, VentasProvider>(
      builder: (context, userProvider, ventasProvider, child) {
        final venta = ventasProvider.ventas.firstWhere(
          (v) => v.id == widget.venta.id,
          orElse: () => widget.venta,
        );
        final items = venta.items;
        final isAdmin = userProvider.currentUser?.role == UserRole.admin;
        final isOwner = venta.userId == userProvider.currentUser?.id;

        final canPick =
            (isOwner || isAdmin) && venta.estado == VentaEstado.SELECCIONANDO;
        final canVerify = isAdmin && venta.estado == VentaEstado.VERIFICANDO;
        final canPack =
            (isOwner || isAdmin) && venta.estado == VentaEstado.EMBALANDO;
        final canDeliver = isAdmin && venta.estado == VentaEstado.LISTA_ENTREGA;
        final isCompleted = venta.estado == VentaEstado.COMPLETADA;
        final isCancelled = venta.estado == VentaEstado.CANCELADA;

        final allPicked = items.isNotEmpty && items.every((i) => i.picked);
        final allVerified =
            items.isNotEmpty && items.every((i) => i.verificado);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              _buildAppBar(venta, canPick),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(venta),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Información del Cliente'),
                      const SizedBox(height: 12),
                      _buildCustomerCard(venta),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSectionTitle('Productos en Reserva'),
                          if (canPick)
                            TextButton.icon(
                              onPressed: _showProductSelectorDialog,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Añadir'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildItemsList(
                        venta,
                        items,
                        canPick,
                        canVerify,
                        isCompleted,
                      ),
                      const SizedBox(height: 24),
                      _buildPriceBreakdown(venta),
                      const SizedBox(height: 24),
                      _buildPhotosSection(venta, canPack, isAdmin),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomSheet: _buildActionPanel(
            venta,
            items,
            canPick,
            canVerify,
            canPack,
            canDeliver,
            isCompleted,
            isCancelled,
            allPicked,
            allVerified,
          ),
        );
      },
    );
  }

  Widget _buildAppBar(Venta venta, bool canDelete) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: AppColors.primary,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Reserva #${venta.id}',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.primary),
            Positioned(
              right: -30,
              bottom: -20,
              child: Icon(
                Icons.receipt_long,
                size: 150,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ],
        ),
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
      ),
      actions: [
        if (canDelete)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: _deleteVenta,
          ),
      ],
    );
  }

  Widget _buildStatusCard(Venta venta) {
    Color color = _getEstadoColor(venta.estado);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_getEstadoIcon(venta.estado), color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado Actual',
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  _getEstadoDisplayName(venta.estado).toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Venta venta) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.person_outline, 'Nombre', venta.nombreCliente),
          if (venta.telefonoCliente.isNotEmpty) ...[
            const Divider(height: 24),
            _buildInfoRow(
              Icons.phone_outlined,
              'Teléfono',
              venta.telefonoCliente,
            ),
          ],
          const Divider(height: 24),
          _buildInfoRow(
            Icons.calendar_month_outlined,
            'Fecha Registro',
            DateFormat('dd MMMM yyyy • HH:mm').format(venta.fecha),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(
    Venta venta,
    List<VentaItem> items,
    bool canPick,
    bool canVerify,
    bool isCompleted,
  ) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey.shade100,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.shopping_basket_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No hay productos en esta lista.',
              style: GoogleFonts.openSans(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildModernItemTile(
          venta,
          item,
          canPick,
          canVerify,
          isCompleted,
        );
      },
    );
  }

  Widget _buildModernItemTile(
    Venta venta,
    VentaItem item,
    bool canPick,
    bool canVerify,
    bool isCompleted,
  ) {
    bool isCheckable =
        (venta.estado == VentaEstado.SELECCIONANDO && canPick) ||
        (venta.estado == VentaEstado.VERIFICANDO && canVerify);
    bool isChecked = venta.estado == VentaEstado.SELECCIONANDO
        ? item.picked
        : item.verificado;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isChecked
              ? AppColors.primary.withOpacity(0.2)
              : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: isCheckable
            ? Checkbox(
                value: isChecked,
                onChanged: (val) {
                  setState(() => isChecked = val ?? false);
                  if (venta.estado == VentaEstado.SELECCIONANDO) {
                    item.picked = isChecked;
                    Provider.of<VentasProvider>(
                      context,
                      listen: false,
                    ).updateItemPicked(item.id!, isChecked);
                  } else {
                    item.verificado = isChecked;
                    Provider.of<VentasProvider>(
                      context,
                      listen: false,
                    ).updateItemVerificado(item.id!, isChecked);
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isChecked
                      ? AppColors.success.withOpacity(0.1)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isChecked ? Icons.check : Icons.inventory_2_outlined,
                  size: 18,
                  color: isChecked ? AppColors.success : Colors.grey,
                ),
              ),
        title: Text(
          item.producto.nombre,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.cantidad} x ${item.esPorPaquete ? "Paquete" : "Unidad"}',
              style: GoogleFonts.openSans(fontSize: 12),
            ),
            Text(
              'Bs. ${(item.cantidad * item.precioVenta).toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        trailing: canPick
            ? IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: AppColors.error,
                  size: 20,
                ),
                onPressed: () => _confirmDeleteItem(item),
              )
            : null,
      ),
    );
  }

  Widget _buildPriceBreakdown(Venta venta) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildPriceRow(
            'Subtotal',
            venta.total,
            Colors.white.withOpacity(0.7),
          ),
          const SizedBox(height: 8),
          _buildPriceRow(
            'Adelanto',
            venta.adelanto,
            Colors.white.withOpacity(0.7),
          ),
          const Divider(color: Colors.white24, height: 24),
          _buildPriceRow(
            'Total Pendiente',
            venta.total - venta.adelanto,
            Colors.white,
            isBold: true,
            fontSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosSection(Venta venta, bool canPack, bool isAdmin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Evidencia de Embalaje'),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: venta.fotosEmbalaje.isEmpty
              ? Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Center(
                    child: Text(
                      'Sin fotos registradas',
                      style: GoogleFonts.openSans(color: AppColors.textMuted),
                    ),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: venta.fotosEmbalaje.length,
                  itemBuilder: (context, index) {
                    final path = venta.fotosEmbalaje[index];
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: FileImage(File(path)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        if (canPack)
                          Positioned(
                            right: 12,
                            top: 0,
                            child: IconButton(
                              icon: const Icon(
                                Icons.cancel,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  _removePackingImage(venta.id!, path),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        if (canPack) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPackingPhoto(venta, ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar Foto'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _pickPackingPhoto(venta, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pickPackingPhoto(Venta venta, ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 70);
    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          'pack_${venta.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = p.join(appDir.path, fileName);
      await File(image.path).copy(savedPath);
      if (!mounted) return;
      await Provider.of<VentasProvider>(
        context,
        listen: false,
      ).addPackingPhoto(venta.id!, savedPath);
      setState(() {});
    }
  }

  Future<void> _removePackingImage(int ventaId, String path) async {
    final provider = Provider.of<VentasProvider>(context, listen: false);
    await provider.removePackingPhoto(ventaId, path);
    setState(() {});
  }

  Widget _buildActionPanel(
    Venta venta,
    List<VentaItem> items,
    bool canPick,
    bool canVerify,
    bool canPack,
    bool canDeliver,
    bool isCompleted,
    bool isCancelled,
    bool allPicked,
    bool allVerified,
  ) {
    if (isCompleted || isCancelled) return const SizedBox.shrink();

    String btnText = "";
    VoidCallback? action;
    Color btnColor = AppColors.primary;

    if (venta.estado == VentaEstado.SELECCIONANDO) {
      btnText = "ENVIAR A VERIFICAR";
      action = allPicked ? _sendToVerification : null;
    } else if (venta.estado == VentaEstado.VERIFICANDO) {
      btnText = "CONFIRMAR VERIFICACIÓN";
      action = allVerified ? _sendToPacking : null;
      btnColor = Colors.orange;
    } else if (venta.estado == VentaEstado.EMBALANDO) {
      btnText = "FINALIZAR EMBALAJE";
      action = (venta.fotosEmbalaje.isNotEmpty) ? _markPackingComplete : null;
      btnColor = Colors.teal;
    } else if (venta.estado == VentaEstado.LISTA_ENTREGA) {
      btnText = "ENTREGAR Y COMPLETAR";
      action = _confirmDelivery;
      btnColor = AppColors.success;
    }

    if (btnText.isEmpty && action == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (venta.estado == VentaEstado.SELECCIONANDO &&
                !allPicked &&
                items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Debes marcar todos los productos para continuar',
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (venta.estado == VentaEstado.EMBALANDO &&
                venta.fotosEmbalaje.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Adjunta al menos una foto del empaque para continuar',
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: Colors.teal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: action,
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  btnText,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helpers
  Widget _buildSectionTitle(String title) => Text(
    title,
    style: GoogleFonts.poppins(
      fontWeight: FontWeight.bold,
      fontSize: 16,
      color: AppColors.primary,
    ),
  );

  Widget _buildInfoRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.primary.withOpacity(0.5)),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.openSans(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildPriceRow(
    String label,
    double value,
    Color color, {
    bool isBold = false,
    double fontSize = 14,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.openSans(
          color: color,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      Text(
        'Bs. ${value.toStringAsFixed(2)}',
        style: GoogleFonts.poppins(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    ],
  );

  Color _getEstadoColor(VentaEstado estado) {
    switch (estado) {
      case VentaEstado.COMPLETADA:
        return AppColors.success;
      case VentaEstado.CANCELADA:
        return AppColors.error;
      case VentaEstado.SELECCIONANDO:
        return Colors.blue;
      case VentaEstado.VERIFICANDO:
        return Colors.orange;
      case VentaEstado.EMBALANDO:
        return Colors.teal;
      case VentaEstado.LISTA_ENTREGA:
        return Colors.purple;
    }
  }

  IconData _getEstadoIcon(VentaEstado estado) {
    switch (estado) {
      case VentaEstado.COMPLETADA:
        return Icons.verified;
      case VentaEstado.CANCELADA:
        return Icons.cancel;
      case VentaEstado.SELECCIONANDO:
        return Icons.shopping_basket;
      case VentaEstado.VERIFICANDO:
        return Icons.fact_check;
      case VentaEstado.EMBALANDO:
        return Icons.inventory_2;
      case VentaEstado.LISTA_ENTREGA:
        return Icons.local_shipping;
    }
  }

  String _getEstadoDisplayName(VentaEstado estado) {
    if (estado == VentaEstado.SELECCIONANDO) return "Borrador - Selección";
    if (estado == VentaEstado.LISTA_ENTREGA) return "Listo para Entregar";
    return estado.name.replaceAll('_', ' ');
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
