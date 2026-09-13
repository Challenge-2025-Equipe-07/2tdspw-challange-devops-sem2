-- =============================================================================
-- script_bd.sql
-- DDL da API Veti — Azure Database for PostgreSQL Flexible Server
-- Banco: db-challenge
-- Time CCGL · Turma 2TDSPW · Challenge 2026 Sprint 3
--
-- Espelha as entidades JPA (nomes, PKs, FKs, uniques e sequences).
-- Na Azure o schema também é aplicado em runtime por
-- SPRING_JPA_HIBERNATE_DDL_AUTO=update. Este arquivo é o DDL oficial
-- para correção (estrutura + comentários).
--
-- Homologação do CRUD: TB_TUTOR (pai) e TB_PET (filho, FK TB_TUTOR_ID_TUTOR).
-- Identificadores entre aspas para preservar maiúsculas no PostgreSQL.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Sequences (GenerationType.SEQUENCE, allocationSize = 1)
-- ---------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS "SQ_TUTOR"               START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_PET"                 START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_VETERINARIO"         START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_CONSULTA"            START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_EXAME"               START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_MEDICAMENTO"         START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_RECEITA"             START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_RECEITA_MEDICAMENTO" START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS "SQ_EXAME_MEDICAMENTO"   START WITH 1 INCREMENT BY 1;

COMMENT ON SEQUENCE "SQ_TUTOR"               IS 'Sequence da PK ID_TUTOR.';
COMMENT ON SEQUENCE "SQ_PET"                 IS 'Sequence da PK ID_PET.';
COMMENT ON SEQUENCE "SQ_VETERINARIO"         IS 'Sequence da PK ID_VETERINARIO.';
COMMENT ON SEQUENCE "SQ_CONSULTA"            IS 'Sequence da PK ID_CONSULTA.';
COMMENT ON SEQUENCE "SQ_EXAME"               IS 'Sequence da PK ID_EXAME.';
COMMENT ON SEQUENCE "SQ_MEDICAMENTO"         IS 'Sequence da PK ID_MEDICAMENTO.';
COMMENT ON SEQUENCE "SQ_RECEITA"             IS 'Sequence da PK ID_RECEITA.';
COMMENT ON SEQUENCE "SQ_RECEITA_MEDICAMENTO" IS 'Sequence da PK ID_PEDIDO em TB_RECEITA_MEDICAMENTO.';
COMMENT ON SEQUENCE "SQ_EXAME_MEDICAMENTO"   IS 'Sequence da PK ID_PEDIDO em TB_EXAME_MEDICAMENTO.';

-- ---------------------------------------------------------------------------
-- TB_TUTOR
-- Tutor (responsável) do pet. Tabela pai do CRUD de homologação.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_TUTOR" (
    "ID_TUTOR"    BIGINT       NOT NULL,
    "NM_TUTOR"    VARCHAR(300) NOT NULL,
    "DS_CPF"      CHAR(11)     NOT NULL,
    "DS_EMAIL"    VARCHAR(320) NOT NULL,
    "DS_TELEFONE" VARCHAR(13)  NULL,
    CONSTRAINT "TB_TUTOR_PK"          PRIMARY KEY ("ID_TUTOR"),
    CONSTRAINT "TB_TUTOR_DS_CPF_UN"   UNIQUE ("DS_CPF"),
    CONSTRAINT "TB_TUTOR_DS_EMAIL_UN" UNIQUE ("DS_EMAIL")
);

COMMENT ON TABLE  "TB_TUTOR"             IS 'Cadastro do tutor (responsável legal) do animal.';
COMMENT ON COLUMN "TB_TUTOR"."ID_TUTOR"    IS 'PK. Identificador do tutor (SQ_TUTOR).';
COMMENT ON COLUMN "TB_TUTOR"."NM_TUTOR"    IS 'Nome completo do tutor. Obrigatório, até 300 caracteres.';
COMMENT ON COLUMN "TB_TUTOR"."DS_CPF"      IS 'CPF com 11 dígitos. Único (TB_TUTOR_DS_CPF_UN).';
COMMENT ON COLUMN "TB_TUTOR"."DS_EMAIL"    IS 'E-mail de contato. Único (TB_TUTOR_DS_EMAIL_UN), até 320 caracteres.';
COMMENT ON COLUMN "TB_TUTOR"."DS_TELEFONE" IS 'Telefone de contato. Opcional, até 13 caracteres.';

-- ---------------------------------------------------------------------------
-- TB_PET
-- Animal vinculado a um tutor (FK). Tabela filha do CRUD de homologação.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_PET" (
    "ID_PET"            BIGINT        NOT NULL,
    "NM_PET"            VARCHAR(100)  NOT NULL,
    "DS_RACA"           VARCHAR(100)  NOT NULL,
    "DS_PESO"           DOUBLE PRECISION NOT NULL,
    "DS_IDADE"          INTEGER       NOT NULL,
    "TB_TUTOR_ID_TUTOR" BIGINT        NOT NULL,
    CONSTRAINT "TB_PET_PK"           PRIMARY KEY ("ID_PET"),
    CONSTRAINT "TB_PET_TB_TUTOR_FK"  FOREIGN KEY ("TB_TUTOR_ID_TUTOR")
        REFERENCES "TB_TUTOR" ("ID_TUTOR")
);

COMMENT ON TABLE  "TB_PET"                    IS 'Cadastro do pet. Relacionado a TB_TUTOR (N:1).';
COMMENT ON COLUMN "TB_PET"."ID_PET"             IS 'PK. Identificador do pet (SQ_PET).';
COMMENT ON COLUMN "TB_PET"."NM_PET"             IS 'Nome do animal. Obrigatório, até 100 caracteres.';
COMMENT ON COLUMN "TB_PET"."DS_RACA"            IS 'Raça (enum da API, ex.: LABRADOR_RETRIEVER, PERSIAN). Obrigatório.';
COMMENT ON COLUMN "TB_PET"."DS_PESO"            IS 'Peso em kg. Obrigatório, deve ser maior que zero.';
COMMENT ON COLUMN "TB_PET"."DS_IDADE"           IS 'Idade em anos (0–99). Obrigatório.';
COMMENT ON COLUMN "TB_PET"."TB_TUTOR_ID_TUTOR"  IS 'FK para TB_TUTOR.ID_TUTOR (TB_PET_TB_TUTOR_FK). Tutor obrigatório.';

-- ---------------------------------------------------------------------------
-- TB_VETERINARIO
-- Usuário autenticado (JWT / Spring Security). Role: USER ou ADMIN.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_VETERINARIO" (
    "ID_VETERINARIO" BIGINT        NOT NULL,
    "DS_EMAIL"       VARCHAR(320)  NOT NULL,
    "DS_PASSWORD"    VARCHAR(5000) NOT NULL,
    "DS_ROLE"        VARCHAR(255)  NULL,
    CONSTRAINT "TB_VETERINARIO_PK"          PRIMARY KEY ("ID_VETERINARIO"),
    CONSTRAINT "TB_VETERINARIO_DS_EMAIL_UN" UNIQUE ("DS_EMAIL")
);

COMMENT ON TABLE  "TB_VETERINARIO"                 IS 'Profissional veterinário. Credencial de login da API.';
COMMENT ON COLUMN "TB_VETERINARIO"."ID_VETERINARIO"  IS 'PK. Identificador do veterinário (SQ_VETERINARIO).';
COMMENT ON COLUMN "TB_VETERINARIO"."DS_EMAIL"        IS 'Login (e-mail). Único (TB_VETERINARIO_DS_EMAIL_UN).';
COMMENT ON COLUMN "TB_VETERINARIO"."DS_PASSWORD"     IS 'Hash BCrypt da senha. Obrigatório.';
COMMENT ON COLUMN "TB_VETERINARIO"."DS_ROLE"         IS 'Perfil de autorização: USER ou ADMIN.';

-- ---------------------------------------------------------------------------
-- TB_CONSULTA
-- Agendamento: um pet + um veterinário em um horário.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_CONSULTA" (
    "ID_CONSULTA"                  BIGINT    NOT NULL,
    "DT_CONSULTA"                  TIMESTAMP NOT NULL,
    "TB_PET_ID_PET"                BIGINT    NOT NULL,
    "TB_VETERINARIO_ID_VETERINARIO" BIGINT   NOT NULL,
    CONSTRAINT "TB_CONSULTA_PK"       PRIMARY KEY ("ID_CONSULTA"),
    CONSTRAINT "TB_CONSULTA_TB_PET_FK" FOREIGN KEY ("TB_PET_ID_PET")
        REFERENCES "TB_PET" ("ID_PET"),
    CONSTRAINT "TB_CON_TB_VET_FK"     FOREIGN KEY ("TB_VETERINARIO_ID_VETERINARIO")
        REFERENCES "TB_VETERINARIO" ("ID_VETERINARIO"),
    CONSTRAINT "TB_CON_DT_VET_UN"     UNIQUE ("DT_CONSULTA", "TB_VETERINARIO_ID_VETERINARIO")
);

COMMENT ON TABLE  "TB_CONSULTA"                              IS 'Consulta clínica. Liga pet e veterinário.';
COMMENT ON COLUMN "TB_CONSULTA"."ID_CONSULTA"                  IS 'PK. Identificador da consulta (SQ_CONSULTA).';
COMMENT ON COLUMN "TB_CONSULTA"."DT_CONSULTA"                  IS 'Data e hora da consulta. Obrigatório.';
COMMENT ON COLUMN "TB_CONSULTA"."TB_PET_ID_PET"                IS 'FK para TB_PET.ID_PET (TB_CONSULTA_TB_PET_FK).';
COMMENT ON COLUMN "TB_CONSULTA"."TB_VETERINARIO_ID_VETERINARIO" IS 'FK para TB_VETERINARIO.ID_VETERINARIO (TB_CON_TB_VET_FK). Único junto com DT_CONSULTA.';

-- ---------------------------------------------------------------------------
-- TB_EXAME
-- Exame solicitado em uma consulta.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_EXAME" (
    "ID_EXAME"                 BIGINT       NOT NULL,
    "DS_EXAME"                 VARCHAR(100) NOT NULL,
    "DS_URL"                   VARCHAR(500) NULL,
    "TB_CONSULTA_ID_CONSULTA"  BIGINT       NOT NULL,
    CONSTRAINT "TB_EXAME_PK"        PRIMARY KEY ("ID_EXAME"),
    CONSTRAINT "TB_EXM_TB_CON_FK"   FOREIGN KEY ("TB_CONSULTA_ID_CONSULTA")
        REFERENCES "TB_CONSULTA" ("ID_CONSULTA")
);

COMMENT ON TABLE  "TB_EXAME"                       IS 'Exame vinculado a uma consulta.';
COMMENT ON COLUMN "TB_EXAME"."ID_EXAME"              IS 'PK. Identificador do exame (SQ_EXAME).';
COMMENT ON COLUMN "TB_EXAME"."DS_EXAME"              IS 'Descrição do exame. Obrigatório, até 100 caracteres.';
COMMENT ON COLUMN "TB_EXAME"."DS_URL"                IS 'URL do laudo/arquivo. Opcional, até 500 caracteres.';
COMMENT ON COLUMN "TB_EXAME"."TB_CONSULTA_ID_CONSULTA" IS 'FK para TB_CONSULTA.ID_CONSULTA (TB_EXM_TB_CON_FK).';

-- ---------------------------------------------------------------------------
-- TB_MEDICAMENTO
-- Catálogo de medicamentos.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_MEDICAMENTO" (
    "ID_MEDICAMENTO" BIGINT       NOT NULL,
    "NM_MEDICAMENTO" VARCHAR(100) NOT NULL,
    "DS_MEDICAMENTO" VARCHAR(400) NOT NULL,
    CONSTRAINT "TB_MEDICAMENTO_PK" PRIMARY KEY ("ID_MEDICAMENTO")
);

COMMENT ON TABLE  "TB_MEDICAMENTO"                 IS 'Catálogo de medicamentos da clínica.';
COMMENT ON COLUMN "TB_MEDICAMENTO"."ID_MEDICAMENTO"  IS 'PK. Identificador do medicamento (SQ_MEDICAMENTO).';
COMMENT ON COLUMN "TB_MEDICAMENTO"."NM_MEDICAMENTO"  IS 'Nome comercial. Obrigatório, até 100 caracteres.';
COMMENT ON COLUMN "TB_MEDICAMENTO"."DS_MEDICAMENTO"  IS 'Descrição. Obrigatório, até 400 caracteres.';

-- ---------------------------------------------------------------------------
-- TB_RECEITA
-- Receita emitida em uma consulta.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_RECEITA" (
    "ID_RECEITA"               BIGINT       NOT NULL,
    "DS_RECEITA"               VARCHAR(500) NOT NULL,
    "TB_CONSULTA_ID_CONSULTA"  BIGINT       NOT NULL,
    CONSTRAINT "TB_RECEITA_PK"   PRIMARY KEY ("ID_RECEITA"),
    CONSTRAINT "TB_RCT_CON_FK"   FOREIGN KEY ("TB_CONSULTA_ID_CONSULTA")
        REFERENCES "TB_CONSULTA" ("ID_CONSULTA")
);

CREATE INDEX IF NOT EXISTS "TB_RECEITA__IDX"
    ON "TB_RECEITA" ("TB_CONSULTA_ID_CONSULTA");

COMMENT ON TABLE  "TB_RECEITA"                       IS 'Receita médica vinculada a uma consulta.';
COMMENT ON COLUMN "TB_RECEITA"."ID_RECEITA"            IS 'PK. Identificador da receita (SQ_RECEITA).';
COMMENT ON COLUMN "TB_RECEITA"."DS_RECEITA"            IS 'Descrição da receita. Obrigatório, até 500 caracteres.';
COMMENT ON COLUMN "TB_RECEITA"."TB_CONSULTA_ID_CONSULTA" IS 'FK para TB_CONSULTA.ID_CONSULTA (TB_RCT_CON_FK).';

-- ---------------------------------------------------------------------------
-- TB_RECEITA_MEDICAMENTO
-- Itens da receita (N:N receita × medicamento) com posologia.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_RECEITA_MEDICAMENTO" (
    "ID_PEDIDO"                    BIGINT        NOT NULL,
    "QT_MEDICAMENTO"               INTEGER       NOT NULL,
    "DS_POSOLOGIA"                 VARCHAR(1000) NOT NULL,
    "TB_RECEITA_ID_RECEITA"        BIGINT        NOT NULL,
    "TB_MEDICAMENTO_ID_MEDICAMENTO" BIGINT       NOT NULL,
    CONSTRAINT "TB_RECEITA_MEDICAMENTO_PK" PRIMARY KEY ("ID_PEDIDO"),
    CONSTRAINT "TB_MEDICAMENTO_RECEITA_FK" FOREIGN KEY ("TB_RECEITA_ID_RECEITA")
        REFERENCES "TB_RECEITA" ("ID_RECEITA"),
    CONSTRAINT "TB_RCT_MDCMNT_FK"          FOREIGN KEY ("TB_MEDICAMENTO_ID_MEDICAMENTO")
        REFERENCES "TB_MEDICAMENTO" ("ID_MEDICAMENTO")
);

COMMENT ON TABLE  "TB_RECEITA_MEDICAMENTO"                         IS 'Item de receita: medicamento + quantidade + posologia.';
COMMENT ON COLUMN "TB_RECEITA_MEDICAMENTO"."ID_PEDIDO"               IS 'PK. Identificador do item (SQ_RECEITA_MEDICAMENTO).';
COMMENT ON COLUMN "TB_RECEITA_MEDICAMENTO"."QT_MEDICAMENTO"          IS 'Quantidade prescrita (1–99). Obrigatório.';
COMMENT ON COLUMN "TB_RECEITA_MEDICAMENTO"."DS_POSOLOGIA"            IS 'Posologia. Obrigatório, até 1000 caracteres.';
COMMENT ON COLUMN "TB_RECEITA_MEDICAMENTO"."TB_RECEITA_ID_RECEITA"   IS 'FK para TB_RECEITA.ID_RECEITA (TB_MEDICAMENTO_RECEITA_FK).';
COMMENT ON COLUMN "TB_RECEITA_MEDICAMENTO"."TB_MEDICAMENTO_ID_MEDICAMENTO" IS 'FK para TB_MEDICAMENTO.ID_MEDICAMENTO (TB_RCT_MDCMNT_FK).';

-- ---------------------------------------------------------------------------
-- TB_EXAME_MEDICAMENTO
-- Medicamentos associados a um exame (mesmo formato de item).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "TB_EXAME_MEDICAMENTO" (
    "ID_PEDIDO"                    BIGINT        NOT NULL,
    "QT_MEDICAMENTO"               INTEGER       NOT NULL,
    "DS_POSOLOGIA"                 VARCHAR(1000) NOT NULL,
    "TB_EXAME_ID_EXAME"            BIGINT        NOT NULL,
    "TB_MEDICAMENTO_ID_MEDICAMENTO" BIGINT       NOT NULL,
    CONSTRAINT "TB_EXAME_MEDICAMENTO_PK" PRIMARY KEY ("ID_PEDIDO"),
    CONSTRAINT "TB_EXM_MED_EXM_FK"       FOREIGN KEY ("TB_EXAME_ID_EXAME")
        REFERENCES "TB_EXAME" ("ID_EXAME"),
    CONSTRAINT "TB_EXM_MDCNT_MDCNT_FK"   FOREIGN KEY ("TB_MEDICAMENTO_ID_MEDICAMENTO")
        REFERENCES "TB_MEDICAMENTO" ("ID_MEDICAMENTO")
);

COMMENT ON TABLE  "TB_EXAME_MEDICAMENTO"                         IS 'Item de medicamento vinculado a um exame.';
COMMENT ON COLUMN "TB_EXAME_MEDICAMENTO"."ID_PEDIDO"               IS 'PK. Identificador do item (SQ_EXAME_MEDICAMENTO).';
COMMENT ON COLUMN "TB_EXAME_MEDICAMENTO"."QT_MEDICAMENTO"          IS 'Quantidade (1–99). Obrigatório.';
COMMENT ON COLUMN "TB_EXAME_MEDICAMENTO"."DS_POSOLOGIA"            IS 'Posologia. Obrigatório, até 1000 caracteres.';
COMMENT ON COLUMN "TB_EXAME_MEDICAMENTO"."TB_EXAME_ID_EXAME"       IS 'FK para TB_EXAME.ID_EXAME (TB_EXM_MED_EXM_FK).';
COMMENT ON COLUMN "TB_EXAME_MEDICAMENTO"."TB_MEDICAMENTO_ID_MEDICAMENTO" IS 'FK para TB_MEDICAMENTO.ID_MEDICAMENTO (TB_EXM_MDCNT_MDCNT_FK).';
