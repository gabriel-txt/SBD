-- Limpeza básica das temporárias (caso já existam)
IF OBJECT_ID('tempdb..#PedidosDia') IS NOT NULL DROP TABLE #PedidosDia;
IF OBJECT_ID('tempdb..#ResumoPedidos') IS NOT NULL DROP TABLE #ResumoPedidos;
IF OBJECT_ID('tempdb..#PedidosAtendidos') IS NOT NULL DROP TABLE #PedidosAtendidos;
IF OBJECT_ID('tempdb..#Estoque') IS NOT NULL DROP TABLE #Estoque;


-- Tabela temporária para receber o conteúdo do TXT
CREATE TABLE #PedidosDia (
    codigoPedido VARCHAR(20),
    dataPedido DATE,
    SKU VARCHAR(50),
    UPC VARCHAR(50),
    nomeProduto VARCHAR(100),
    qtd INT,
    valor VARCHAR(20),
    frete VARCHAR(20),
    email VARCHAR(100),
    codigoComprador VARCHAR(50),
    nomeComprador VARCHAR(100),
    endereco VARCHAR(150),
    CEP VARCHAR(20),
    UF VARCHAR(10),
    pais VARCHAR(50)
);


-- Importando o arquivo
BULK INSERT #PedidosDia
FROM './pedidos.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ';',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001'
);


-- Inserindo clientes
INSERT INTO clientes (
    codigoComprador, nomeComprador, email, endereco, CEP, UF, pais
)
SELECT DISTINCT
    p.codigoComprador, p.nomeComprador, p.email,
    p.endereco, p.CEP, p.UF, p.pais
FROM #PedidosDia p
WHERE NOT EXISTS (
    SELECT 1 FROM clientes c WHERE c.codigoComprador = p.codigoComprador
);


-- Inserindo produtos
INSERT INTO produtos (
    SKU, UPC, nomeProduto, valorUnitario
)
SELECT DISTINCT
    p.SKU,
    p.UPC,
    p.nomeProduto,
    CAST(REPLACE(p.valor, ',', '.') AS DECIMAL(10,2))
FROM #PedidosDia p
WHERE NOT EXISTS (
    SELECT 1 FROM produtos pr WHERE pr.SKU = p.SKU
);


-- Inserindo itens de compra
INSERT INTO compra (
    codigoPedido, SKU, nomeProduto, quantidade, valorUnitario
)
SELECT
    p.codigoPedido,
    p.SKU,
    p.nomeProduto,
    p.qtd,
    CAST(REPLACE(p.valor, ',', '.') AS DECIMAL(10,2))
FROM #PedidosDia p
WHERE NOT EXISTS (
    SELECT 1 FROM compra c 
    WHERE c.codigoPedido = p.codigoPedido AND c.SKU = p.SKU
);


-- Consolidação dos pedidos
SELECT
    codigoPedido,
    MIN(dataPedido) AS dataPedido,
    MAX(codigoComprador) AS codigoComprador,
    SUM(CAST(REPLACE(valor, ',', '.') AS DECIMAL(10,2)) * qtd) AS valorItens,
    MAX(CAST(REPLACE(frete, ',', '.') AS DECIMAL(10,2))) AS frete
INTO #ResumoPedidos
FROM #PedidosDia
GROUP BY codigoPedido;


-- Inserindo pedidos
INSERT INTO pedidos (
    codigoPedido, codigoComprador, valorTotal
)
SELECT
    r.codigoPedido,
    r.codigoComprador,
    r.valorItens + r.frete
FROM #ResumoPedidos r
WHERE NOT EXISTS (
    SELECT 1 FROM pedidos p WHERE p.codigoPedido = r.codigoPedido
);


-- Inserindo expedição (todos inicialmente)
INSERT INTO expedicao (codigoPedido)
SELECT codigoPedido
FROM #PedidosAtendidos pa
WHERE NOT EXISTS (
    SELECT 1 FROM expedicao e WHERE e.codigoPedido = pa.codigoPedido
);

-- Simulação de atendimento dos pedidos (priorizando os mais caros)

-- Simulação de estoque
CREATE TABLE #Estoque (
    SKU VARCHAR(50),
    estoque INT
);

INSERT INTO #Estoque VALUES
('brinq456rio', 1),
('brinq789rio', 1),
('roupa123rio', 1);


-- Tabela de pedidos atendidos
CREATE TABLE #PedidosAtendidos (
    codigoPedido VARCHAR(20),
    valorTotal DECIMAL(10,2)
);


DECLARE @codigoPedido VARCHAR(20);
DECLARE @valorTotal DECIMAL(10,2);
DECLARE @podeAtender BIT;


DECLARE cursor_pedidos CURSOR FOR
SELECT codigoPedido, (valorItens + frete) AS valorTotal
FROM #ResumoPedidos
ORDER BY valorTotal DESC;


OPEN cursor_pedidos;
FETCH NEXT FROM cursor_pedidos INTO @codigoPedido, @valorTotal;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @podeAtender = 1;

    -- Verifica estoque
    IF EXISTS (
        SELECT 1
        FROM #PedidosDia p
        JOIN #Estoque e ON e.SKU = p.SKU
        WHERE p.codigoPedido = @codigoPedido
        AND e.estoque < p.qtd
    )
    BEGIN
        SET @podeAtender = 0;
    END

    -- Se puder atender
    IF @podeAtender = 1
    BEGIN
        -- Baixa no estoque
        UPDATE e
        SET e.estoque = e.estoque - p.qtd
        FROM #Estoque e
        JOIN #PedidosDia p ON p.SKU = e.SKU
        WHERE p.codigoPedido = @codigoPedido;

        -- Marca como atendido
        INSERT INTO #PedidosAtendidos
        VALUES (@codigoPedido, @valorTotal);
    END

    FETCH NEXT FROM cursor_pedidos INTO @codigoPedido, @valorTotal;
END

CLOSE cursor_pedidos;
DEALLOCATE cursor_pedidos;


------------------------------------------------------------
-- RESULTADOS
------------------------------------------------------------

SELECT * FROM clientes;
SELECT * FROM produtos;
SELECT * FROM compra;
SELECT * FROM pedidos;
SELECT * FROM expedicao;

-- NOVO RESULTADO IMPORTANTE
SELECT * FROM #PedidosAtendidos;

-- Estoque final
SELECT * FROM #Estoque;