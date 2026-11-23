// 1. Унікальні обмеження та індекси
CREATE CONSTRAINT user_id_unique IF NOT EXISTS FOR (u:User) REQUIRE u.userId IS UNIQUE;
CREATE CONSTRAINT movie_id_unique IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE CONSTRAINT genre_name_unique IF NOT EXISTS FOR (g:Genre) REQUIRE g.name IS UNIQUE;

// 2. завантаження вузлів User
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender = row.gender,
    u.age = toInteger(row.age),
    u.occupation = toInteger(row.occupation);

// 3. Завантаження вузлів Movie та Genre
LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
WITH row,
     toInteger(substring(row.title, size(row.title) - 5, 4)) AS releaseYear,
     trim(substring(row.title, 0, size(row.title) - 6)) AS cleanTitle,
     split(row.genres, '|') AS genreList
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = cleanTitle,
    m.year = releaseYear
WITH m, genreList
UNWIND genreList AS genreName
MERGE (g:Genre {name: trim(genreName)})
MERGE (m)-[:HAS_GENRE]->(g);

// 4. Батчове завантаження ребер RATED
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM 'file:///ratings.csv' AS row RETURN row",
  "MATCH (u:User {userId: toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating = toFloat(row.rating),
       r.timestamp = toInteger(row.timestamp)",
  {batchSize: 10000, parallel: false}
);

// 5. Перевірка кількості завантажених даних
MATCH (u:User) RETURN count(u) AS users;
MATCH (m:Movie) RETURN count(m) AS movies;
MATCH (g:Genre) RETURN count(g) AS genres;
MATCH ()-[r:RATED]->() RETURN count(r) AS ratings;
