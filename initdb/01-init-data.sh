#!/bin/bash
set -e;

if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
    echo "SETUP INFO: Creando usuarios, estructura dimensional (Star Schema) e insertando datos iniciales para Spring Valley DW..."

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL

        -- 1. Configuracion de Base de Datos y Extensiones
        ALTER DATABASE ${POSTGRES_DB} SET timezone TO '${TIMEZONE}';

        -- 2. Creacion de Usuario ETL (No-Root con privilegios DDL/DML)
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_NON_ROOT_USER}') THEN
                CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
            END IF;
        END
        \$\$;

        GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
        GRANT ALL ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};

        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${POSTGRES_NON_ROOT_USER};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${POSTGRES_NON_ROOT_USER};

        -- 3. Creacion opcional de Usuario Analitico BI (Solo Lectura - PL/pgSQL Nativo)
        DO \$\$
        DECLARE
            bi_user TEXT := '${ANALYTICS_USER:-}';
            bi_pass TEXT := '${ANALYTICS_PASSWORD:-}';
        BEGIN
            IF bi_user <> '' AND NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = bi_user) THEN
                EXECUTE format('CREATE USER %I WITH PASSWORD %L', bi_user, bi_pass);
                EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', '${POSTGRES_DB}', bi_user);
                EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', bi_user);
                EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO %I', bi_user);
            END IF;
        END
        \$\$;

        -- 4. Estructura del Modelo Dimensional (Metodologia Ralph Kimball)
        
        -- 4.1 Dimension Tiempo
        CREATE TABLE IF NOT EXISTS public.dim_tiempo (
            id_tiempo INT PRIMARY KEY,
            fecha DATE NOT NULL UNIQUE,
            anio SMALLINT NOT NULL,
            trimestre SMALLINT NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
            mes SMALLINT NOT NULL CHECK (mes BETWEEN 1 AND 12),
            nombre_mes VARCHAR(15) NOT NULL,
            semana_anio SMALLINT NOT NULL,
            dia_mes SMALLINT NOT NULL CHECK (dia_mes BETWEEN 1 AND 31),
            dia_semana SMALLINT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
            nombre_dia VARCHAR(15) NOT NULL,
            es_fin_semana BOOLEAN NOT NULL DEFAULT false,
            es_festivo BOOLEAN NOT NULL DEFAULT false
        );

        -- 4.2 Dimension Cliente
        CREATE TABLE IF NOT EXISTS public.dim_cliente (
            id_cliente INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            cliente_bk VARCHAR(50) NOT NULL UNIQUE,
            tipo_documento VARCHAR(10) NOT NULL,
            documento_identidad VARCHAR(25) NOT NULL,
            nombre_completo VARCHAR(150) NOT NULL,
            correo_electronico VARCHAR(100),
            telefono VARCHAR(25),
            tipo_cliente VARCHAR(30) DEFAULT 'Regular',
            segmento_mercado VARCHAR(50) DEFAULT 'Retail',
            ciudad VARCHAR(50),
            departamento_estado VARCHAR(50),
            pais VARCHAR(50) DEFAULT 'Colombia',
            fecha_registro DATE DEFAULT CURRENT_DATE
        );

        -- 4.3 Dimension Producto
        CREATE TABLE IF NOT EXISTS public.dim_producto (
            id_producto INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            producto_bk VARCHAR(50) NOT NULL UNIQUE,
            nombre_producto VARCHAR(150) NOT NULL,
            categoria VARCHAR(50) NOT NULL,
            subcategoria VARCHAR(50),
            marca VARCHAR(50),
            unidad_medida VARCHAR(20) DEFAULT 'Unidad',
            precio_base_catalogo NUMERIC(12,2) NOT NULL DEFAULT 0.00,
            costo_estandar NUMERIC(12,2) NOT NULL DEFAULT 0.00,
            estado_activo BOOLEAN NOT NULL DEFAULT true
        );

        -- 4.4 Dimension Sucursal
        CREATE TABLE IF NOT EXISTS public.dim_sucursal (
            id_sucursal INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            sucursal_bk VARCHAR(50) NOT NULL UNIQUE,
            nombre_sucursal VARCHAR(100) NOT NULL,
            canal_venta VARCHAR(30) NOT NULL CHECK (canal_venta IN ('Fisico', 'Online', 'Distribuidor')),
            ciudad VARCHAR(50) NOT NULL,
            departamento_estado VARCHAR(50) NOT NULL,
            direccion VARCHAR(150),
            gerente_sucursal VARCHAR(100),
            fecha_apertura DATE
        );

        -- 4.5 Dimension Metodo de Pago
        CREATE TABLE IF NOT EXISTS public.dim_metodo_pago (
            id_metodo_pago INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            metodo_pago_bk VARCHAR(30) NOT NULL UNIQUE,
            nombre_metodo VARCHAR(50) NOT NULL,
            tipo_flujo VARCHAR(30) NOT NULL,
            proveedor_pasarela VARCHAR(50),
            aplica_comision BOOLEAN DEFAULT false,
            porcentaje_comision NUMERIC(5,2) DEFAULT 0.00
        );

        -- 4.6 Tabla Central de Hechos: Fact_Ventas
        CREATE TABLE IF NOT EXISTS public.fact_ventas (
            id_hecho_venta BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            numero_factura VARCHAR(50) NOT NULL,
            linea_factura INT NOT NULL,
            id_tiempo INT NOT NULL,
            id_cliente INT NOT NULL,
            id_producto INT NOT NULL,
            id_sucursal INT NOT NULL,
            id_metodo_pago INT NOT NULL,
            cantidad_vendida INT NOT NULL CHECK (cantidad_vendida > 0),
            precio_unitario NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
            costo_unitario NUMERIC(12,2) NOT NULL CHECK (costo_unitario >= 0),
            monto_descuento NUMERIC(12,2) NOT NULL DEFAULT 0.00,
            impuesto_iva NUMERIC(12,2) NOT NULL DEFAULT 0.00,
            monto_bruto NUMERIC(14,2) NOT NULL,
            monto_neto NUMERIC(14,2) NOT NULL,
            margen_ganancia NUMERIC(14,2) NOT NULL,
            fecha_carga TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT uq_factura_linea UNIQUE (numero_factura, linea_factura)
        );

        -- 5. Restricciones Foreign Key (Integridad Referencial OLAP)
        ALTER TABLE public.fact_ventas
            ADD CONSTRAINT fk_ventas_tiempo FOREIGN KEY (id_tiempo) REFERENCES public.dim_tiempo (id_tiempo) ON UPDATE NO ACTION ON DELETE RESTRICT,
            ADD CONSTRAINT fk_ventas_cliente FOREIGN KEY (id_cliente) REFERENCES public.dim_cliente (id_cliente) ON UPDATE NO ACTION ON DELETE RESTRICT,
            ADD CONSTRAINT fk_ventas_producto FOREIGN KEY (id_producto) REFERENCES public.dim_producto (id_producto) ON UPDATE NO ACTION ON DELETE RESTRICT,
            ADD CONSTRAINT fk_ventas_sucursal FOREIGN KEY (id_sucursal) REFERENCES public.dim_sucursal (id_sucursal) ON UPDATE NO ACTION ON DELETE RESTRICT,
            ADD CONSTRAINT fk_ventas_metodo_pago FOREIGN KEY (id_metodo_pago) REFERENCES public.dim_metodo_pago (id_metodo_pago) ON UPDATE NO ACTION ON DELETE RESTRICT;

        -- 6. Indices B-Tree para optimizacion de Star Joins
        CREATE INDEX IF NOT EXISTS idx_ventas_tiempo ON public.fact_ventas (id_tiempo);
        CREATE INDEX IF NOT EXISTS idx_ventas_cliente ON public.fact_ventas (id_cliente);
        CREATE INDEX IF NOT EXISTS idx_ventas_producto ON public.fact_ventas (id_producto);
        CREATE INDEX IF NOT EXISTS idx_ventas_sucursal ON public.fact_ventas (id_sucursal);
        CREATE INDEX IF NOT EXISTS idx_ventas_metodo_pago ON public.fact_ventas (id_metodo_pago);
        CREATE INDEX IF NOT EXISTS idx_ventas_num_factura ON public.fact_ventas (numero_factura);

        -- 7. Asignacion de Propiedad al Usuario de Mantenimiento / ETL
        ALTER TABLE public.dim_tiempo OWNER TO ${POSTGRES_NON_ROOT_USER};
        ALTER TABLE public.dim_cliente OWNER TO ${POSTGRES_NON_ROOT_USER};
        ALTER TABLE public.dim_producto OWNER TO ${POSTGRES_NON_ROOT_USER};
        ALTER TABLE public.dim_sucursal OWNER TO ${POSTGRES_NON_ROOT_USER};
        ALTER TABLE public.dim_metodo_pago OWNER TO ${POSTGRES_NON_ROOT_USER};
        ALTER TABLE public.fact_ventas OWNER TO ${POSTGRES_NON_ROOT_USER};

        -- Si existe usuario analitico, garantizarle permisos de lectura (PL/pgSQL Nativo)
        DO \$\$
        DECLARE
            bi_user TEXT := '${ANALYTICS_USER:-}';
        BEGIN
            IF bi_user <> '' THEN
                EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA public TO %I', bi_user);
            END IF;
        END
        \$\$;

        -- 8. Poblar Datos Semilla Maestros (Calibracion Inicial de Spring Valley)
        
        INSERT INTO public.dim_metodo_pago (metodo_pago_bk, nombre_metodo, tipo_flujo, proveedor_pasarela, aplica_comision, porcentaje_comision)
        VALUES 
            ('MP-EFEC', 'Efectivo en Caja', 'Efectivo', 'Caja Central', false, 0.00),
            ('MP-TC-VISA', 'Tarjeta Credito Visa', 'Credito', 'CredibanCo', true, 1.85),
            ('MP-TC-MC', 'Tarjeta Credito MasterCard', 'Credito', 'Redeban', true, 1.85),
            ('MP-TD-DEB', 'Tarjeta Debito Maestro/Visa', 'Debito', 'CredibanCo', true, 1.10),
            ('MP-TRANSF', 'Transferencia Bancaria / PSE', 'Transferencia', 'ACH Colombia', false, 0.50)
        ON CONFLICT (metodo_pago_bk) DO NOTHING;

        INSERT INTO public.dim_sucursal (sucursal_bk, nombre_sucursal, canal_venta, ciudad, departamento_estado, direccion, gerente_sucursal, fecha_apertura)
        VALUES 
            ('SUC-NORTE', 'Spring Valley Sede Norte', 'Fisico', 'Cali', 'Valle del Cauca', 'Av. 6N # 28-10', 'Carlos H. Morales', '2023-01-15'),
            ('SUC-SUR', 'Spring Valley Sede Sur', 'Fisico', 'Cali', 'Valle del Cauca', 'Calle 5 # 66-20', 'Laura Restrepo', '2023-06-01'),
            ('SUC-ECOMM', 'Tienda Virtual Oficial', 'Online', 'Nacional', 'Central', 'https://store.springvalley.co', 'Andrea Gómez', '2023-10-01')
        ON CONFLICT (sucursal_bk) DO NOTHING;

        INSERT INTO public.dim_producto (producto_bk, nombre_producto, categoria, subcategoria, marca, unidad_medida, precio_base_catalogo, costo_estandar)
        VALUES 
            ('SKU-001', 'Panel Solar Portatil 100W', 'Energia y Exterior', 'Generadores', 'ValleyPower', 'Unidad', 450000.00, 290000.00),
            ('SKU-002', 'Bateria Estacionaria Litio 12V', 'Energia y Exterior', 'Baterias', 'EcoVolt', 'Unidad', 820000.00, 560000.00),
            ('SKU-003', 'Kit Filtro Purificador Pro', 'Hogar y Confort', 'Tratamiento Agua', 'PureFlow', 'Kit', 180000.00, 110000.00),
            ('SKU-004', 'Sensor Ambiental IoT Temp/Hum', 'Domotica y Monitoreo', 'Sensores', 'SmartValley', 'Unidad', 95000.00, 52000.00)
        ON CONFLICT (producto_bk) DO NOTHING;

        INSERT INTO public.dim_cliente (cliente_bk, tipo_documento, documento_identidad, nombre_completo, correo_electronico, telefono, tipo_cliente, segmento_mercado, ciudad, departamento_estado)
        VALUES 
            ('CLI-1001', 'CC', '1144001122', 'Alejandro Vargas Silva', 'a.vargas@empresa.com', '3104567890', 'Corporativo', 'B2B', 'Cali', 'Valle del Cauca'),
            ('CLI-1002', 'CC', '1144002233', 'Mariana Duque Ruiz', 'mduque@gmail.com', '3157891234', 'Final', 'B2C', 'Cali', 'Valle del Cauca'),
            ('CLI-1003', 'NIT', '901234567-1', 'Industrias Verdes del Valle SAS', 'compras@inverdes.co', '3209876543', 'Mayorista', 'B2B', 'Yumbo', 'Valle del Cauca')
        ON CONFLICT (cliente_bk) DO NOTHING;

        INSERT INTO public.dim_tiempo (id_tiempo, fecha, anio, trimestre, mes, nombre_mes, semana_anio, dia_mes, dia_semana, nombre_dia, es_fin_semana, es_festivo)
        VALUES 
            (20260924, '2026-09-24', 2026, 3, 9, 'Septiembre', 39, 24, 4, 'Jueves', false, false),
            (20260925, '2026-09-25', 2026, 3, 9, 'Septiembre', 39, 25, 5, 'Viernes', false, false)
        ON CONFLICT (id_tiempo) DO NOTHING;

        INSERT INTO public.fact_ventas (
            numero_factura, linea_factura, id_tiempo, id_cliente, id_producto, id_sucursal, id_metodo_pago,
            cantidad_vendida, precio_unitario, costo_unitario, monto_descuento, impuesto_iva, monto_bruto, monto_neto, margen_ganancia
        )
        VALUES 
            ('FAC-2026-0001', 1, 20260924, 1, 1, 1, 2, 2, 450000.00, 290000.00, 0.00, 171000.00, 900000.00, 1071000.00, 320000.00),
            ('FAC-2026-0001', 2, 20260924, 1, 4, 1, 2, 3, 95000.00, 52000.00, 15000.00, 51300.00, 270000.00, 321300.00, 114000.00),
            ('FAC-2026-0002', 1, 20260925, 2, 3, 3, 4, 1, 180000.00, 110000.00, 0.00, 34200.00, 180000.00, 214200.00, 70000.00)
        ON CONFLICT (numero_factura, linea_factura) DO NOTHING;

EOSQL

    echo "SETUP INFO: Estructura dimensional y datos semilla para Spring Valley cargados con éxito."
else
    echo "SETUP INFO: Variables POSTGRES_NON_ROOT_USER y POSTGRES_NON_ROOT_PASSWORD no definidas. Se omitió la creación automática."
fi