// ==========================================
// ЧАСТИНА 5.1. PAGERANK НА ГРАФІ ФІЛЬМІВ (GDS)
// ==========================================

// Крок 1: Матеріалізуємо ребра фільм-фільм через спільних користувачів (оцінка >= 4)
// Оптимізовано для Neo4j 5.18: використовуємо COUNT {} та попередню фільтрацію популярних фільмів
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4.0 AND r2.rating >= 4.0
  AND m1.movieId < m2.movieId
  AND COUNT { (m1)<-[:RATED]-() } > 20
  AND COUNT { (m2)<-[:RATED]-() } > 20
WITH m1, m2, count(u) AS weight
ORDER BY weight DESC
LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;


// Крок 2: Створюємо проєкцію графа в пам'яті GDS
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  {
    CO_RATED: {
      orientation: 'UNDIRECTED',
      properties: 'weight'
    }
  }
)
YIELD graphName, nodeCount, relationshipCount;


// Крок 3: Запускаємо зважений алгоритм PageRank (враховуємо вагу спільних оцінок weight)
CALL gds.pageRank.stream('movieGraph', {
  maxIterations: 20,
  dampingFactor: 0.85,
  relationshipWeightProperty: 'weight'
})
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS movie, score
RETURN movie.movieId AS movieId,
       movie.title AS title,
       movie.year AS year,
       round(score, 4) AS pageRankScore,
       COUNT { (movie)<-[:RATED]-() } AS totalRatings
ORDER BY pageRankScore DESC
LIMIT 15;


// Крок 4: Очищаємо пам'ять GDS та видаляємо тимчасові ребра CO_RATED
CALL gds.graph.drop('movieGraph') YIELD graphName;
MATCH ()-[co:CO_RATED]-() DELETE co;

// ==========================================
// ЧАСТИНА 5.2. ВИЯВЛЕННЯ СПІЛЬНОТ (LOUVAIN)
// ==========================================

// Крок 1: Матеріалізуємо ребра схожості користувачів за найвищими оцінками (rating = 5.0, мінімум 20 спільних фільмів)
// Використано поріг rating = 5.0 та попередній фільтр активності COUNT >= 100, щоб уникнути
// переповнення транзакційної пам'яті (1.4 GiB) через супервузли та прискорити розрахунок
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5.0 AND r2.rating = 5.0
  AND u1.userId < u2.userId
  AND COUNT { (u1)-[:RATED]->() } >= 100
  AND COUNT { (u2)-[:RATED]->() } >= 100
WITH u1, u2, count(m) AS weight
WHERE weight >= 20
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;


// Крок 2: Створюємо проєкцію графа схожості користувачів у пам'яті GDS
CALL gds.graph.project(
  'userSimilarity',
  'User',
  {
    SIMILAR: {
      orientation: 'UNDIRECTED',
      properties: 'weight'
    }
  }
)
YIELD graphName, nodeCount, relationshipCount;


// Крок 3: Запускаємо Louvain (режим write записує communityId у вузли User і повертає modularity)
CALL gds.louvain.write('userSimilarity', {
  relationshipWeightProperty: 'weight',
  writeProperty: 'communityId'
})
YIELD communityCount, modularity, modularities;


// Крок 4a: Аналізуємо розподіл користувачів за кластерами (топ-10 найбільших спільнот)
MATCH (u:User)
WHERE u.communityId IS NOT NULL
WITH u.communityId AS communityId, count(u) AS clusterSize
ORDER BY clusterSize DESC
LIMIT 10
RETURN communityId, clusterSize;


// Крок 4b: Визначаємо топ-3 найпопулярніші жанри (за оцінками >= 4) для кожної з топ-10 спільнот
MATCH (u:User)
WHERE u.communityId IS NOT NULL
WITH u.communityId AS communityId, collect(u) AS users, count(u) AS clusterSize
ORDER BY clusterSize DESC
LIMIT 10
UNWIND users AS u
MATCH (u)-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4.0
WITH communityId, clusterSize, g.name AS genre, count(r) AS highRatingsCount
ORDER BY communityId, highRatingsCount DESC
WITH communityId, clusterSize, collect({genre: genre, count: highRatingsCount})[0..3] AS topGenres
RETURN communityId,
       clusterSize,
       [x IN topGenres | x.genre + ' (' + toString(x.count) + ')'] AS top3Genres
ORDER BY clusterSize DESC;


// Крок 5: Очищаємо проєкцію GDS, тимчасові ребра SIMILAR та властивість communityId
CALL gds.graph.drop('userSimilarity') YIELD graphName;
MATCH (u:User) REMOVE u.communityId;

// ==========================================
// ЧАСТИНА 5.3. НАЙКОРОТШИЙ ШЛЯХ (АЛГОРИТМ ДЕЙКСТРИ)
// ==========================================

// Крок 1:
// Додаємо обернену вагу cost = 1.0 / weight (щоб більша схожість означала меншу "відстань" для Дейкстри)
MATCH ()-[sim:SIMILAR]-()
SET sim.cost = 1.0 / sim.weight;


// Крок 2: Створюємо проєкцію 'userGraph' із властивістю відстані 'cost'
CALL gds.graph.project(
  'userGraph',
  'User',
  {
    SIMILAR: {
      orientation: 'UNDIRECTED',
      properties: ['weight', 'cost']
    }
  }
)
YIELD graphName, nodeCount, relationshipCount;


// Крок 3a: Запускаємо алгоритм Дейкстри між кількома парами активних користувачів
// (порівнюємо користувачів із різних кластерів, наприклад, 4169 -> 1680 та 4169 -> 1015)
UNWIND [
  [4169, 1680],
  [4169, 1015],
  [1680, 4277],
  [53, 1941]
] AS pair
MATCH (source:User {userId: pair[0]}), (target:User {userId: pair[1]})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'cost'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN pair[0] AS startUser,
       pair[1] AS endUser,
       size(nodeIds) - 1 AS hops,
       size(nodeIds) - 2 AS intermediateUsers,
       round(totalCost, 4) AS semanticDistance,
       [n IN nodes(path) | 'User ' + toString(n.userId)] AS chain;


// Крок 3b: Оцінюємо середню довжину шляху («тісний світ») через вибірку 200 випадкових пар зв'язаних користувачів
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH collect(u) AS connectedUsers
WITH connectedUsers, size(connectedUsers) AS totalConnected
UNWIND range(1, 200) AS i
WITH connectedUsers[toInteger(rand() * totalConnected)] AS u1,
     connectedUsers[toInteger(rand() * totalConnected)] AS u2
WHERE u1 <> u2
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: u1,
  targetNode: u2,
  relationshipWeightProperty: 'cost'
})
YIELD nodeIds
RETURN count(*) AS reachablePairs,
       round(avg(size(nodeIds) - 1), 2) AS avgHops,
       min(size(nodeIds) - 1) AS minHops,
       max(size(nodeIds) - 1) AS maxHops;


// Крок 4: Очищаємо проєкцію 'userGraph' та тимчасові ребра [:SIMILAR]
CALL gds.graph.drop('userGraph') YIELD graphName;
MATCH ()-[sim:SIMILAR]-() DELETE sim;