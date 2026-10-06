CREATE TABLE IF NOT EXISTS public.dim_cliente
(
    id_cliente integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    cliente_bk character varying(50) COLLATE pg_catalog."default" NOT NULL,
    tipo_documento character varying(10) COLLATE pg_catalog."default" NOT NULL,
    documento_identidad character varying(25) COLLATE pg_catalog."default" NOT NULL,
    nombre_completo character varying(150) COLLATE pg_catalog."default" NOT NULL,
    correo_electronico character varying(100) COLLATE pg_catalog."default",
    telefono character varying(25) COLLATE pg_catalog."default",
    tipo_cliente character varying(30) COLLATE pg_catalog."default" DEFAULT 'Regular'::character varying,
    segmento_mercado character varying(50) COLLATE pg_catalog."default" DEFAULT 'Retail'::character varying,
    ciudad character varying(50) COLLATE pg_catalog."default",
    departamento_estado character varying(50) COLLATE pg_catalog."default",
    pais character varying(50) COLLATE pg_catalog."default" DEFAULT 'Colombia'::character varying,
    fecha_registro date DEFAULT CURRENT_DATE,
    CONSTRAINT dim_cliente_pkey PRIMARY KEY (id_cliente),
    CONSTRAINT dim_cliente_cliente_bk_key UNIQUE (cliente_bk)
);

CREATE TABLE IF NOT EXISTS public.dim_metodo_pago
(
    id_metodo_pago integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    metodo_pago_bk character varying(30) COLLATE pg_catalog."default" NOT NULL,
    nombre_metodo character varying(50) COLLATE pg_catalog."default" NOT NULL,
    tipo_flujo character varying(30) COLLATE pg_catalog."default" NOT NULL,
    proveedor_pasarela character varying(50) COLLATE pg_catalog."default",
    aplica_comision boolean DEFAULT false,
    porcentaje_comision numeric(5, 2) DEFAULT 0.00,
    CONSTRAINT dim_metodo_pago_pkey PRIMARY KEY (id_metodo_pago),
    CONSTRAINT dim_metodo_pago_metodo_pago_bk_key UNIQUE (metodo_pago_bk)
);

CREATE TABLE IF NOT EXISTS public.dim_producto
(
    id_producto integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    producto_bk character varying(50) COLLATE pg_catalog."default" NOT NULL,
    nombre_producto character varying(150) COLLATE pg_catalog."default" NOT NULL,
    categoria character varying(50) COLLATE pg_catalog."default" NOT NULL,
    subcategoria character varying(50) COLLATE pg_catalog."default",
    marca character varying(50) COLLATE pg_catalog."default",
    unidad_medida character varying(20) COLLATE pg_catalog."default" DEFAULT 'Unidad'::character varying,
    precio_base_catalogo numeric(12, 2) NOT NULL DEFAULT 0.00,
    costo_estandar numeric(12, 2) NOT NULL DEFAULT 0.00,
    estado_activo boolean NOT NULL DEFAULT true,
    CONSTRAINT dim_producto_pkey PRIMARY KEY (id_producto),
    CONSTRAINT dim_producto_producto_bk_key UNIQUE (producto_bk)
);

CREATE TABLE IF NOT EXISTS public.dim_sucursal
(
    id_sucursal integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    sucursal_bk character varying(50) COLLATE pg_catalog."default" NOT NULL,
    nombre_sucursal character varying(100) COLLATE pg_catalog."default" NOT NULL,
    canal_venta character varying(30) COLLATE pg_catalog."default" NOT NULL,
    ciudad character varying(50) COLLATE pg_catalog."default" NOT NULL,
    departamento_estado character varying(50) COLLATE pg_catalog."default" NOT NULL,
    direccion character varying(150) COLLATE pg_catalog."default",
    gerente_sucursal character varying(100) COLLATE pg_catalog."default",
    fecha_apertura date,
    CONSTRAINT dim_sucursal_pkey PRIMARY KEY (id_sucursal),
    CONSTRAINT dim_sucursal_sucursal_bk_key UNIQUE (sucursal_bk)
);

CREATE TABLE IF NOT EXISTS public.dim_tiempo
(
    id_tiempo integer NOT NULL,
    fecha date NOT NULL,
    anio smallint NOT NULL,
    trimestre smallint NOT NULL,
    mes smallint NOT NULL,
    nombre_mes character varying(15) COLLATE pg_catalog."default" NOT NULL,
    semana_anio smallint NOT NULL,
    dia_mes smallint NOT NULL,
    dia_semana smallint NOT NULL,
    nombre_dia character varying(15) COLLATE pg_catalog."default" NOT NULL,
    es_fin_semana boolean NOT NULL DEFAULT false,
    es_festivo boolean NOT NULL DEFAULT false,
    CONSTRAINT dim_tiempo_pkey PRIMARY KEY (id_tiempo),
    CONSTRAINT dim_tiempo_fecha_key UNIQUE (fecha)
);

CREATE TABLE IF NOT EXISTS public.fact_ventas
(
    id_hecho_venta bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    numero_factura character varying(50) COLLATE pg_catalog."default" NOT NULL,
    linea_factura integer NOT NULL,
    id_tiempo integer NOT NULL,
    id_cliente integer NOT NULL,
    id_producto integer NOT NULL,
    id_sucursal integer NOT NULL,
    id_metodo_pago integer NOT NULL,
    cantidad_vendida integer NOT NULL,
    precio_unitario numeric(12, 2) NOT NULL,
    costo_unitario numeric(12, 2) NOT NULL,
    monto_descuento numeric(12, 2) NOT NULL DEFAULT 0.00,
    impuesto_iva numeric(12, 2) NOT NULL DEFAULT 0.00,
    monto_bruto numeric(14, 2) NOT NULL,
    monto_neto numeric(14, 2) NOT NULL,
    margen_ganancia numeric(14, 2) NOT NULL,
    fecha_carga timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fact_ventas_pkey PRIMARY KEY (id_hecho_venta),
    CONSTRAINT uq_factura_linea UNIQUE (numero_factura, linea_factura)
);

ALTER TABLE IF EXISTS public.fact_ventas
    ADD CONSTRAINT fk_ventas_cliente FOREIGN KEY (id_cliente)
    REFERENCES public.dim_cliente (id_cliente) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_ventas_cliente
    ON public.fact_ventas(id_cliente);


ALTER TABLE IF EXISTS public.fact_ventas
    ADD CONSTRAINT fk_ventas_metodo_pago FOREIGN KEY (id_metodo_pago)
    REFERENCES public.dim_metodo_pago (id_metodo_pago) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_ventas_metodo_pago
    ON public.fact_ventas(id_metodo_pago);


ALTER TABLE IF EXISTS public.fact_ventas
    ADD CONSTRAINT fk_ventas_producto FOREIGN KEY (id_producto)
    REFERENCES public.dim_producto (id_producto) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_ventas_producto
    ON public.fact_ventas(id_producto);


ALTER TABLE IF EXISTS public.fact_ventas
    ADD CONSTRAINT fk_ventas_sucursal FOREIGN KEY (id_sucursal)
    REFERENCES public.dim_sucursal (id_sucursal) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_ventas_sucursal
    ON public.fact_ventas(id_sucursal);


ALTER TABLE IF EXISTS public.fact_ventas
    ADD CONSTRAINT fk_ventas_tiempo FOREIGN KEY (id_tiempo)
    REFERENCES public.dim_tiempo (id_tiempo) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_ventas_tiempo
    ON public.fact_ventas(id_tiempo);

END;