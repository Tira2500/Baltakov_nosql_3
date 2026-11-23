// ==========================================
// ЧАСТИНА 4. ВИЯВЛЕННЯ СУПЕРВУЗЛІВ (SUPERNODES)
// ==========================================

// Запит 1. Загальний топ-15 вузлів графа за кількістю зв'язків (ступенем вузла)
MATCH (n)
WITH n, labels(n)[0] AS nodeType, COUNT { (n)--() } AS degree
RETURN nodeType,
       coalesce(n.title, n.name, 'User ' + toString(n.userId)) AS entityName,
       degree
ORDER BY degree DESC
LIMIT 15;


// Запит 2. Аналіз супервузлів серед жанрів (:Genre)
MATCH (g:Genre)
WITH g, COUNT { (g)<-[:HAS_GENRE]-() } AS moviesInGenre
RETURN g.name AS genre,
       moviesInGenre
ORDER BY moviesInGenre DESC;


// Запит 3. Топ-10 фільмів-супервузлів (:Movie) за кількістю оцінок
MATCH (m:Movie)
WITH m,
     COUNT { (m)<-[:RATED]-() } AS ratingCount,
     COUNT { (m)-[:HAS_GENRE]->() } AS genreCount
RETURN m.movieId AS movieId,
       m.title AS title,
       m.year AS year,
       ratingCount,
       (ratingCount + genreCount) AS totalDegree
ORDER BY ratingCount DESC
LIMIT 10;


// Запит 4. Топ-10 найактивніших користувачів-супервузлів (:User)
MATCH (u:User)
WITH u, COUNT { (u)-[:RATED]->() } AS ratedMoviesCount
RETURN u.userId AS userId,
       u.gender AS gender,
       u.age AS age,
       ratedMoviesCount
ORDER BY ratedMoviesCount DESC
LIMIT 10;