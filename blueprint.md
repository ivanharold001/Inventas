
# Blueprint: Aplicación de Inventario en Flutter

## Visión General

Esta es una aplicación móvil de inventario creada con Flutter. Permite a los usuarios llevar un registro de productos, incluyendo su nombre, marca, ubicación, precios, stock y una foto. Los datos se almacenan localmente en una base de datos SQLite.

## Características Implementadas

*   **Listado de productos:** Muestra todos los productos en una lista clara y fácil de leer.
*   **Búsqueda:** Permite buscar productos por nombre o marca.
*   **Gestión de Productos Completa:** Formularios para agregar y editar productos con campos para nombre, marca, ubicación, precio de paquete, precio por unidad y stock.
*   **Eliminar producto:** Permite eliminar productos del inventario con un diálogo de confirmación.
*   **Modal de Detalles:** Al tocar un producto, se muestra un modal con la foto en grande y todos los detalles del mismo.
*   **Almacenamiento local:** Usa `sqflite` para guardar los datos de forma persistente en el dispositivo, con migraciones automáticas de la base de datos.
*   **Gestión de estado:** Utiliza el paquete `provider` para gestionar el estado de la aplicación de forma eficiente.
*   **Diseño personalizado:** La aplicación tiene un tema visual coherente y agradable.

## Plan para la Próxima Iteración: Añadir Precio y Stock (¡Completado!)

### 1. Modelo y Base de Datos
- [x] **Actualizar `Product` Model (`lib/main.dart`):**
    - Añadir `final double precioPaquete;`
    - Añadir `final double precioUnidad;`
    - Añadir `final int stock;`
    - Actualizar los métodos `toMap()` y `fromMap()`.
- [x] **Actualizar `DatabaseHelper` (`lib/main.dart`):**
    - Incrementar la versión de la base de datos a `2`.
    - Implementar el método `_onUpgrade` en `openDatabase`.
    - En `_onUpgrade`, ejecutar `ALTER TABLE` para añadir las columnas `precio_paquete`, `precio_unidad` y `stock`.
    - Actualizar la sentencia `CREATE TABLE` en `_onCreate` para incluir los nuevos campos en instalaciones nuevas.

### 2. Interfaz de Usuario (`lib/main.dart`)
- [x] **Actualizar `AddProductScreen` y `EditProductScreen`:**
    - Añadir `TextEditingController` para los nuevos campos.
    - Añadir `TextFormField`s para "Precio del Paquete", "Precio por Unidad" y "Stock".
    - Usar `TextInputType.number` como tipo de teclado para estos campos.
    - Actualizar los métodos de guardado para parsear y almacenar los nuevos valores.
- [x] **Actualizar la Vista de Lista (`ProductListScreen`):**
    - Añadir la información de stock y precios en el `Card` de cada producto para una visualización rápida.
- [x] **Actualizar el Modal (`_showProductDetailModal`):**
    - Mostrar los nuevos campos de precio y stock en el diálogo de detalles.
