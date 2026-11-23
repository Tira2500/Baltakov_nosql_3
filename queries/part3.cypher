// ==========================================
// БАЗОВІ ЗАПИТИ
// ==========================================

// Запит 1. Знайти всі фільми жанру «Thriller» із середнім рейтингом вище 4.0
MATCH (u:User)-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre {name: "Thriller"})
WITH m, avg(r.rating) AS avgRating, count(r) AS ratingCount
WHERE avgRating > 4.0
RETURN m.movieId AS movieId,
       m.title AS title,
       m.year AS year,
       round(avgRating, 2) AS avgRating,
       ratingCount
ORDER BY avgRating DESC, ratingCount DESC;


// Запит 2. Знайти користувачів, які поставили оцінку 5 більш ніж 50 фільмам
MATCH (u:User)-[r:RATED]->(m:Movie)
WHERE r.rating = 5.0
WITH u, count(m) AS fiveStarCount
WHERE fiveStarCount > 50
RETURN u.userId AS userId,
       u.gender AS gender,
       u.age AS age,
       fiveStarCount
ORDER BY fiveStarCount DESC;


// ==========================================
// ЗАПИТИ СЕРЕДНЬОГО РІВНЯ
// ==========================================

// Запит 3. Знайти фільми, які обидва користувачі (userId=1 і userId=2) оцінили високо (рейтинг >= 4)
MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4.0 AND r2.rating >= 4.0
RETURN m.movieId AS movieId,
       m.title AS title,
       m.year AS year,
       r1.rating AS ratingUser1,
       r2.rating AS ratingUser2,
       (r1.rating + r2.rating) / 2.0 AS pairAvgRating
ORDER BY pairAvgRating DESC, m.title ASC;


// Запит 4. Знайти жанри, чиї фільми стабільно отримують високі оцінки — середній рейтинг і кількість оцінок
MATCH (u:User)-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre)
WITH g.name AS genre,
     avg(r.rating) AS avgRating,
     count(r) AS totalRatings,
     count(DISTINCT m) AS moviesCount
RETURN genre,
       round(avgRating, 3) AS avgRating,
       totalRatings,
       moviesCount
ORDER BY avgRating DESC, totalRatings DESC;


// ==========================================
// СКЛАДНІ ЗАПИТИ
// ==========================================

// Запит 5. Рекомендація «користувачі зі схожими смаками також дивилися» (для userId = 1)
// Крок 1: Знаходимо користувачів (peer), які високо оцінили (>= 4) ті самі фільми, що й цільовий користувач (мінімум 5 спільних хітів)
MATCH (target:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(peer:User)
WHERE r1.rating >= 4.0 AND r2.rating >= 4.0 AND target <> peer
WITH target, peer, count(m) AS commonLikedMovies
WHERE commonLikedMovies >= 5

// Крок 2: Знаходимо інші фільми, які високо оцінили ці "близнюки" за смаком, але цільовий користувач ще не бачив
MATCH (peer)-[r3:RATED]->(rec:Movie)
WHERE r3.rating >= 4.0 AND NOT EXISTS { (target)-[:RATED]->(rec) }
RETURN rec.movieId AS movieId,
       rec.title AS title,
       rec.year AS year,
       count(DISTINCT peer) AS recommendedByPeers,
       round(avg(r3.rating), 2) AS avgPeerRating
ORDER BY recommendedByPeers DESC, avgPeerRating DESC
LIMIT 15;


// Запит 6. Знайти найкоротший ланцюжок зв’язку між двома користувачами через спільні фільми
MATCH (u1:User {userId: 1}), (u2:User {userId: 6040})
MATCH path = shortestPath((u1)-[:RATED*]-(u2))
RETURN path,
       length(path) AS hops,
       [n IN nodes(path) | CASE WHEN n:User THEN 'User ' + toString(n.userId) ELSE n.title END] AS chain;