-- =========================================
-- 1. LIMPEZA INICIAL
-- =========================================
DROP DATABASE IF EXISTS loja;
CREATE DATABASE loja;
USE loja;

-- =========================================
-- 2. TABELA STAGING (IMPORTAÇÃO DO TXT)
-- =========================================
CREATE TABLE staging_pedidos (
    codigoPedido VARCHAR(20),
    dataPedido DATE,
    SKU VARCHAR(50),
    UPC VARCHAR(20),
    nomeProduto VARCHAR(100),
    qtd INT,
    valor DECIMAL(10,2),
    frete DECIMAL(10,2),
    email VARCHAR(100),
    codigoComprador INT,
    nomeComprador VARCHAR(100),
    endereco VARCHAR(200),
    CEP VARCHAR(20),
    UF VARCHAR(5),
    pais VARCHAR(50)
);

-- =========================================
-- 3. INSERT DOS DADOS (pedidos.txt)
-- =========================================
INSERT INTO staging_pedidos VALUES
('abc123','2024-03-19','brinq456rio','456','quebra-cabeca',1,43.22,5.32,'samir@gmail.com',123,'Samir','Rua Exemplo 1','21212322','RJ','Brasil'),
('abc123','2024-03-19','brinq789rio','789','jogo',1,43.22,5.32,'samir@gmail.com',123,'Samir','Rua Exemplo 1','21212322','RJ','Brasil'),
('abc789','2024-03-20','roupa123rio','123','camisa',2,47.25,6.21,'teste@gmail.com',789,'Fulano','Rua Exemplo 2','14784520','RJ','Brasil'),
('abc741','2024-03-21','brinq789rio','789','jogo',1,43.22,5.32,'samir@gmail.com',123,'Samir','Rua Exemplo 1','21212322','RJ','Brasil');

-- =========================================
-- 4. MODELAGEM DAS TABELAS DO SISTEMA
-- =========================================

CREATE TABLE clientes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    codigoComprador INT,
    nome VARCHAR(100),
    email VARCHAR(100),
    endereco VARCHAR(200),
    CEP VARCHAR(20),
    UF VARCHAR(5),
    pais VARCHAR(50)
);

CREATE TABLE produtos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    SKU VARCHAR(50),
    nome VARCHAR(100),
    valor DECIMAL(10,2)
);

CREATE TABLE estoque (
    id INT AUTO_INCREMENT PRIMARY KEY,
    produto_id INT,
    quantidade INT,
    FOREIGN KEY (produto_id) REFERENCES produtos(id)
);

CREATE TABLE pedidos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    codigoPedido VARCHAR(20),
    cliente_id INT,
    dataPedido DATE,
    valor_total DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'Pendente',
    FOREIGN KEY (cliente_id) REFERENCES clientes(id)
);

CREATE TABLE itens_pedido (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pedido_id INT,
    produto_id INT,
    qtd INT,
    valor_unitario DECIMAL(10,2),
    FOREIGN KEY (pedido_id) REFERENCES pedidos(id),
    FOREIGN KEY (produto_id) REFERENCES produtos(id)
);

CREATE TABLE expedicao (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pedido_id INT,
    status VARCHAR(20),
    FOREIGN KEY (pedido_id) REFERENCES pedidos(id)
);

-- =========================================
-- 5. ATIVIDADE 1
-- =========================================

-- CLIENTES
INSERT INTO clientes (codigoComprador, nome, email, endereco, CEP, UF, pais)
SELECT DISTINCT codigoComprador, nomeComprador, email, endereco, CEP, UF, pais
FROM staging_pedidos;

-- PRODUTOS
INSERT INTO produtos (SKU, nome, valor)
SELECT DISTINCT SKU, nomeProduto, valor
FROM staging_pedidos;

-- ESTOQUE (VALORES MOCKADOS)
INSERT INTO estoque (produto_id, quantidade)
SELECT id, 10 FROM produtos;

-- PEDIDOS
INSERT INTO pedidos (codigoPedido, cliente_id, dataPedido, valor_total)
SELECT 
    sp.codigoPedido,
    c.id,
    sp.dataPedido,
    SUM(sp.valor * sp.qtd) + MAX(sp.frete)
FROM staging_pedidos sp
JOIN clientes c ON c.codigoComprador = sp.codigoComprador
GROUP BY sp.codigoPedido, c.id, sp.dataPedido;

-- ITENS DO PEDIDO
INSERT INTO itens_pedido (pedido_id, produto_id, qtd, valor_unitario)
SELECT 
    p.id,
    pr.id,
    sp.qtd,
    sp.valor
FROM staging_pedidos sp
JOIN pedidos p ON p.codigoPedido = sp.codigoPedido
JOIN produtos pr ON pr.SKU = sp.SKU;

-- EXPEDIÇÃO
INSERT INTO expedicao (pedido_id, status)
SELECT id, 'Aguardando'
FROM pedidos;

-- =========================================
-- 6. ATIVIDADE 2 (CURSOR - PRIORIZAÇÃO)
-- =========================================
DELIMITER $$

CREATE PROCEDURE priorizar_pedidos()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_pedido_id INT;

    DECLARE cur CURSOR FOR
        SELECT p.id
        FROM pedidos p
        ORDER BY p.valor_total DESC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    loop_pedidos: LOOP
        FETCH cur INTO v_pedido_id;
        IF done THEN
            LEAVE loop_pedidos;
        END IF;

        -- Verifica se todos os itens têm estoque suficiente
        IF NOT EXISTS (
            SELECT 1
            FROM itens_pedido ip
            JOIN estoque e ON e.produto_id = ip.produto_id
            WHERE ip.pedido_id = v_pedido_id
            AND e.quantidade < ip.qtd
        ) THEN
            UPDATE pedidos
            SET status = 'Prioritário'
            WHERE id = v_pedido_id;
        END IF;

    END LOOP;

    CLOSE cur;
END $$

DELIMITER ;

-- =========================================
-- 7. ATIVIDADE 3 (CURSOR - ATENDIMENTO)
-- =========================================
DELIMITER $$

CREATE PROCEDURE atender_pedidos()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_pedido_id INT;

    DECLARE cur CURSOR FOR
        SELECT id FROM pedidos WHERE status = 'Prioritário';

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    loop_atendimento: LOOP
        FETCH cur INTO v_pedido_id;
        IF done THEN
            LEAVE loop_atendimento;
        END IF;

        -- Baixa estoque
        UPDATE estoque e
        JOIN itens_pedido ip ON e.produto_id = ip.produto_id
        SET e.quantidade = e.quantidade - ip.qtd
        WHERE ip.pedido_id = v_pedido_id;

        -- Atualiza status
        UPDATE pedidos
        SET status = 'Atendido'
        WHERE id = v_pedido_id;

    END LOOP;

    CLOSE cur;
END $$

DELIMITER ;

-- =========================================
-- 8. EXECUÇÃO
-- =========================================

CALL priorizar_pedidos();
CALL atender_pedidos();

-- =========================================
-- 9. CONSULTA FINAL
-- =========================================
SELECT * FROM pedidos;