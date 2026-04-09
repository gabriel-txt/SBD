-- Limpeza básica das temporárias (caso já existam)
IF OBJECT_ID('tempdb..#PedidosDia') IS NOT NULL DROP TABLE #PedidosDia;
IF OBJECT_ID('tempdb..#ResumoPedidos') IS NOT NULL DROP TABLE #ResumoPedidos;


-- Tabela temporária para receber o conteúdo do TXT
CREATE TABLE #PedidosDia (
    codigoPedido VARCHAR(20),
    dataPedido DATE,
    SKU VARCHAR(50),
    UPC VARCHAR(50),
    nomeProduto VARCHAR(100),
    qtd INT,
    valor VARCHAR(20),   -- vem com vírgula
    frete VARCHAR(20),  -- vem com vírgula
    email VARCHAR(100),
    codigoComprador VARCHAR(50),
    nomeComprador VARCHAR(100),
    endereco VARCHAR(150),
    CEP VARCHAR(20),
    UF VARCHAR(10),
    pais VARCHAR(50)
);


-- Importando o arquivo (ajustar caminho se necessário)
BULK INSERT #PedidosDia
FROM 'C:\temp\pedidos.txt'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ';',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001'
);


-- Inserindo clientes (evita duplicados)
INSERT INTO clientes (
    codigoComprador,
    nomeComprador,
    email,
    endereco,
    CEP,
    UF,
    pais
)
SELECT DISTINCT
    p.codigoComprador,
    p.nomeComprador,
    p.email,
    p.endereco,
    p.CEP,
    p.UF,
    p.pais
FROM #PedidosDia p
WHERE NOT EXISTS (
    SELECT 1
    FROM clientes c
    WHERE c.codigoComprador = p.codigoComprador
);


-- Inserindo produtos novos
INSERT INTO produtos (
    SKU,
    UPC,
    nomeProduto,
    valorUnitario
)
SELECT DISTINCT
    p.SKU,
    p.UPC,
    p.nomeProduto,
    CAST(REPLACE(p.valor, ',', '.') AS DECIMAL(10,2))
FROM #PedidosDia p
WHERE NOT EXISTS (
    SELECT 1
    FROM produtos pr
    WHERE pr.SKU = p.SKU
);


-- Cada linha do arquivo vira um item na tabela compra
INSERT INTO compra (
    codigoPedido,
    SKU,
    nomeProduto,
    quantidade,
    valorUnitario
)
SELECT
    p.codigoPedido,
    p.SKU,
    p.nomeProduto,
    p.qtd,
    CAST(REPLACE(p.valor, ',', '.') AS DECIMAL(10,2))
FROM #PedidosDia p
WHERE NOT EXISTS (
    SELECT 1
    FROM compra c
    WHERE c.codigoPedido = p.codigoPedido
      AND c.SKU = p.SKU
);


-- Consolida o total dos pedidos
-- (soma dos itens + frete)
SELECT
    codigoPedido,
    MIN(dataPedido) AS dataPedido,
    MAX(codigoComprador) AS codigoComprador,
    SUM(CAST(REPLACE(valor, ',', '.') AS DECIMAL(10,2)) * qtd) AS valorItens,
    MAX(CAST(REPLACE(frete, ',', '.') AS DECIMAL(10,2))) AS frete
INTO #ResumoPedidos
FROM #PedidosDia
GROUP BY codigoPedido;


-- Inserindo os pedidos já com o valor total calculado
INSERT INTO pedidos (
    codigoPedido,
    codigoComprador,
    valorTotal
)
SELECT
    r.codigoPedido,
    r.codigoComprador,
    r.valorItens + r.frete
FROM #ResumoPedidos r
WHERE NOT EXISTS (
    SELECT 1
    FROM pedidos p
    WHERE p.codigoPedido = r.codigoPedido
);


-- Envia para expedição (um registro por pedido)
INSERT INTO expedicao (
    codigoPedido
)
SELECT DISTINCT
    r.codigoPedido
FROM #ResumoPedidos r
WHERE NOT EXISTS (
    SELECT 1
    FROM expedicao e
    WHERE e.codigoPedido = r.codigoPedido
);


-- Conferência final
SELECT * FROM clientes;
SELECT * FROM produtos;
SELECT * FROM compra;
SELECT * FROM pedidos;
SELECT * FROM expedicao;