-- ============================
-- CREACIÓN DE TABLAS
-- ============================

-- Tabla de Roles
CREATE TABLE Rol (
    id_rol INT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    descripcion TEXT
);

-- Tabla de Usuarios
CREATE TABLE Usuario (
    id_usuario INT PRIMARY KEY,
    nombre_usuario VARCHAR(100) NOT NULL,
    ubicacion_usuario VARCHAR(100) NOT NULL,
    contraseña VARCHAR(100) NOT NULL,
    correo VARCHAR(100) NOT NULL UNIQUE,
    id_rol INT NOT NULL,
    FOREIGN KEY (id_rol) REFERENCES Rol(id_rol)
);

-- Tabla de Categorías
CREATE TABLE Categoria (
    id_categoria INT PRIMARY KEY,
    nombre_categoria VARCHAR(50) NOT NULL
);

-- Tabla de Videojuegos
CREATE TABLE Videojuego (
    id_videojuego INT PRIMARY KEY,
    nombre_videojuego VARCHAR(50) NOT NULL,
    descripcion VARCHAR(200),
    precio INT NOT NULL,
    stock INT NOT NULL,
    url_imagen VARCHAR(200),
    id_categoria INT,
    id_usuario INT,
    FOREIGN KEY (id_categoria) REFERENCES Categoria(id_categoria),
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)
);

ALTER TABLE Videojuego
ADD CONSTRAINT chk_stock_no_negativo CHECK (stock >= 0);


-- Tabla de Carritos
CREATE TABLE Carrito (
    id_carrito INT PRIMARY KEY,
    id_usuario INT NOT NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    estado VARCHAR(20) DEFAULT 'activo',
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)
);

-- Tabla de Detalles del Carrito
CREATE TABLE Carrito_Detalle (
    id_detalle INT PRIMARY KEY,
    id_carrito INT NOT NULL,
    id_videojuego INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario INT NOT NULL,
    FOREIGN KEY (id_carrito) REFERENCES Carrito(id_carrito),
    FOREIGN KEY (id_videojuego) REFERENCES Videojuego(id_videojuego)
);

-- Tabla de Compras
CREATE TABLE Compra (
    id_compra INT PRIMARY KEY,
    id_usuario INT NOT NULL,
    medio_de_pago VARCHAR(50) NOT NULL,
    precio_total INT NOT NULL,
    boleta_factura VARCHAR(100),
    fecha_compra DATE NOT NULL,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)
);

-- Tabla de Detalles de Compra
CREATE TABLE Compra_Detalle (
    id_detalle_compra INT PRIMARY KEY,
    id_compra INT NOT NULL,
    id_videojuego INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario INT NOT NULL,
    FOREIGN KEY (id_compra) REFERENCES Compra(id_compra),
    FOREIGN KEY (id_videojuego) REFERENCES Videojuego(id_videojuego)
);

-- Tabla de Valoraciones
CREATE TABLE Valoracion (
    id_valoracion INT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_videojuego INT NOT NULL,
    estrellas INT NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
    comentario VARCHAR(100),
    restricciones VARCHAR(100),
    fecha_valoracion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_videojuego) REFERENCES Videojuego(id_videojuego),
    UNIQUE (id_usuario, id_videojuego)
);

-- Tabla de Rankings
CREATE TABLE Ranking (
    id_ranking INT PRIMARY KEY,
    tipo_de_ranking VARCHAR(50) NOT NULL,
    id_videojuego INT NOT NULL,
    puntuacion_promedio NUMERIC(3,1),
    FOREIGN KEY (id_videojuego) REFERENCES Videojuego(id_videojuego)
);

-- Tabla de Lista de Deseos
CREATE TABLE Lista_Deseos (
    id_lista INT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_videojuego INT NOT NULL,
    fecha_agregado TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_videojuego) REFERENCES Videojuego(id_videojuego),
    UNIQUE (id_usuario, id_videojuego)
);

CREATE TABLE Auditoria_Videojuego (
    id_auditoria SERIAL PRIMARY KEY,
    id_videojuego INT,
    nombre_videojuego VARCHAR(100),
    id_usuario INT,
    accion VARCHAR(20), -- 'INSERT', 'UPDATE', 'DELETE'
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Auditoria_Stock (
    id_auditoria SERIAL PRIMARY KEY,
    id_videojuego INT,
    nombre_videojuego VARCHAR(100),
    stock_anterior INT,
    stock_nuevo INT,
    accion VARCHAR(10),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- ============================
-- CREATE DE VIEW
-- ============================

CREATE VIEW ranking_mas_vendidos AS
SELECT 
    v.id_videojuego,
    v.nombre_videojuego,
    SUM(cd.cantidad) AS total_vendidos
FROM 
    compra_detalle cd
JOIN 
    videojuego v ON cd.id_videojuego = v.id_videojuego
GROUP BY 
    v.id_videojuego, v.nombre_videojuego
ORDER BY 
    total_vendidos DESC;

CREATE VIEW ranking_mas_deseados AS
SELECT v.id_videojuego, v.nombre_videojuego, COUNT(ld.id_lista) as total_deseado
FROM videojuego v
LEFT JOIN lista_deseos ld ON v.id_videojuego = ld.id_videojuego
GROUP BY v.id_videojuego, v.nombre_videojuego
ORDER BY total_deseado DESC;

-- ========================================
-- TRIGGER
-- ========================================

--Función que valida el stock
CREATE OR REPLACE FUNCTION validar_stock()
RETURNS TRIGGER AS $$
DECLARE
    stock_actual INT;
BEGIN
    -- Buscar el stock actual del videojuego que se quiere comprar
    SELECT stock INTO stock_actual
    FROM Videojuego
    WHERE id_videojuego = NEW.id_videojuego;

    -- Verificar si existe
    IF stock_actual IS NULL THEN
        RAISE EXCEPTION 'El videojuego con ID % no existe.', NEW.id_videojuego;
    END IF;

    -- Validar si hay stock suficiente
    IF stock_actual < NEW.cantidad THEN
        RAISE EXCEPTION 'No hay stock suficiente para el videojuego con ID % (stock actual: %, cantidad pedida: %)',
            NEW.id_videojuego, stock_actual, NEW.cantidad;
    END IF;

    -- Si todo bien, continuar con el insert
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger que usa la función
CREATE TRIGGER trigger_validar_stock
BEFORE INSERT ON Compra_Detalle
FOR EACH ROW
EXECUTE FUNCTION validar_stock();

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION limpiar_carrito_post_compra(uid INT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM Carrito_Detalle
    WHERE id_carrito IN (SELECT id_carrito FROM Carrito WHERE id_usuario = uid);
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION descontar_stock()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Videojuego
    SET stock = stock - NEW.cantidad
    WHERE id_videojuego = NEW.id_videojuego;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_descontar_stock
AFTER INSERT ON Compra_Detalle
FOR EACH ROW
EXECUTE FUNCTION descontar_stock();

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION reporte_ventas_usuario(uid INT)
RETURNS TABLE (
    nombre_videojuego VARCHAR,
    fecha_compra DATE,
    cantidad INT,
    precio_unitario INT,
    total INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.nombre_videojuego,
        c.fecha_compra,
        cd.cantidad,
        cd.precio_unitario,
        cd.cantidad * cd.precio_unitario
    FROM Compra c
    JOIN Compra_Detalle cd ON c.id_compra = cd.id_compra
    JOIN Videojuego v ON v.id_videojuego = cd.id_videojuego
    WHERE c.id_usuario = uid
    ORDER BY c.fecha_compra DESC;
END;
$$;

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION registrar_auditoria_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Auditoria_Videojuego (
        id_videojuego,
        nombre_videojuego,
        id_usuario,
        accion
    ) VALUES (
        NEW.id_videojuego,
        NEW.nombre_videojuego,
        NEW.id_usuario,
        'INSERT'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditoria_insert
AFTER INSERT ON Videojuego
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria_insert();

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION auditar_actualizacion_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stock IS DISTINCT FROM NEW.stock THEN
        INSERT INTO Auditoria_Stock (
            id_videojuego,
            nombre_videojuego,
            stock_anterior,
            stock_nuevo,
            accion
        )
        VALUES (
            OLD.id_videojuego,
            OLD.nombre_videojuego,
            OLD.stock,
            NEW.stock,
            'UPDATE'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- TRIGGER
-- ========================================

CREATE TRIGGER trg_auditoria_stock
AFTER UPDATE ON Videojuego
FOR EACH ROW
EXECUTE FUNCTION auditar_actualizacion_stock();

CREATE OR REPLACE FUNCTION evitar_eliminar_videojuegos_comprados()
RETURNS TRIGGER AS $$
DECLARE
    existe_compra INT;
BEGIN
    -- Verificar si existe al menos una compra asociada al videojuego
    SELECT COUNT(*) INTO existe_compra
    FROM Compra_Detalle
    WHERE id_videojuego = OLD.id_videojuego;

    -- Si existe una compra, lanzar un error y evitar el DELETE
    IF existe_compra > 0 THEN
        RAISE EXCEPTION 'Operación bloqueada: el videojuego con ID % ya ha sido comprado.', OLD.id_videojuego;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_evitar_delete_videojuegos_comprados
BEFORE DELETE ON Videojuego
FOR EACH ROW
EXECUTE FUNCTION evitar_eliminar_videojuegos_comprados();

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE PROCEDURE actualizar_precio_categoria(
    nombre_categoria_param VARCHAR,
    porcentaje_aumento NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE Videojuego
    SET precio = precio + (precio * (porcentaje_aumento / 100))
    WHERE id_categoria = (
        SELECT id_categoria
        FROM Categoria
        WHERE LOWER(nombre_categoria) = LOWER(nombre_categoria_param)
    );
END;
$$;

-- ========================================
-- TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION reporte_ventas_usuario(uid INT)
RETURNS TABLE (
    nombre_videojuego VARCHAR,
    fecha_compra DATE,
    cantidad INT,
    precio_unitario INT,
    total INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.nombre_videojuego,
        c.fecha_compra,
        cd.cantidad,
        cd.precio_unitario,
        cd.cantidad * cd.precio_unitario
    FROM Compra c
    JOIN Compra_Detalle cd ON c.id_compra = cd.id_compra
    JOIN Videojuego v ON v.id_videojuego = cd.id_videojuego
    WHERE c.id_usuario = uid
    ORDER BY c.fecha_compra DESC;
END;
$$;