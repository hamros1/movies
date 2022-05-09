class GetAMovie::Jobs::PullSuggestionsJob < GetAMovie::Jobs::BaseJob
  QUERY_POPULAR_MOVIES = <<-SQL
  SELECT * FROM movies WHERE popularity::numeric > 0 ORDER BY popularity::numeric DESC LIMIT 24
  SQL

  QUERY_POPULAR_TV = <<-SQL
  SELECT * FROM tv WHERE popularity::numeric > 0 ORDER BY popularity::numeric DESC LIMIT 24
  SQL

  QUERY_TOP_RATED_MOVIES = <<-SQL
  SELECT * FROM movies WHERE average_rating::numeric > 0 ORDER BY average_rating::numeric DESC LIMIT 24 
  SQL

  QUERY_TOP_RATED_TV = <<-SQL
  SELECT * FROM tv WHERE average_rating::numeric > 0 ORDER BY average_rating::numeric DESC LIMIT 24
  SQL

  QUERY_ACTION_ADVENTURE_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Action%') OR
    (array_to_string(genres, ', ') LIKE '%Adventure%') ORDER BY random()
  SQL

  QUERY_COMEDY_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Comedy%') ORDER BY random()
  SQL

  QUERY_DRAMA_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Drama%') ORDER BY random()
  SQL

  QUERY_FANTASY_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Fantasy%') ORDER BY random()
  SQL

  QUERY_HORROR_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Horror%') ORDER BY random()
  SQL

  QUERY_MILITARY_AND_WAR_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Military%') OR
    (array_to_string(genres, ', ') LIKE '%War%') ORDER BY random()
  SQL

  QUERY_MYSTERY_AND_THRILLER_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Mystery%') OR
    (array_to_string(genres, ', ') LIKE '%Thriller%') ORDER BY random()
  SQL

  QUERY_ROMANCE_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Romance%') ORDER BY random()
  SQL

  QUERY_SCIENCE_FICTION_MOVIES = <<-SQL
    SELECT * FROM movies WHERE
    (array_to_string(genres, ', ') LIKE '%Science Fiction%') ORDER BY random()
  SQL

  POPULAR_MOVIES = Atomic.new([] of Video)
  POPULAR_TV = Atomic.new([] of TV)
  TOP_RATED_MOVIES = Atomic.new([] of Video)
  TOP_RATED_TV = Atomic.new([] of TV)
  ACTION_AND_ADVENTURE_MOVIES = Atomic.new([] of Video)
  COMEDY_MOVIES = Atomic.new([] of Video)
  DRAMA_MOVIES = Atomic.new([] of Video)
  FANTASY_MOVIES = Atomic.new([] of Video)
  HORROR_MOVIES = Atomic.new([] of Video)
  MILITARY_AND_WAR_MOVIES = Atomic.new([] of Video)
  MYSTERY_AND_THRILLER_MOVIES = Atomic.new([] of Video)
  ROMANCE_MOVIES = Atomic.new([] of Video)
  SCIENCE_FICTION_MOVIES = Atomic.new([] of Video)

  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      popular_movies = db.query_all(QUERY_POPULAR_MOVIES, as: Video)
      popular_tv = db.query_all(QUERY_POPULAR_TV, as: TV)
      top_rated_movies = db.query_all(QUERY_TOP_RATED_MOVIES, as: Video)
      top_rated_tv = db.query_all(QUERY_TOP_RATED_TV, as: TV)
      action_and_adventure_movies = db.query_all(QUERY_ACTION_ADVENTURE_MOVIES, as: Video)
      comedy_movies = db.query_all(QUERY_COMEDY_MOVIES, as: Video)
      drama_movies = db.query_all(QUERY_DRAMA_MOVIES, as: Video)
      fantasy_movies = db.query_all(QUERY_FANTASY_MOVIES, as: Video)
      horror_movies = db.query_all(QUERY_HORROR_MOVIES, as: Video)
      military_and_war_movies = db.query_all(QUERY_MILITARY_AND_WAR_MOVIES, as: Video)
      mystery_and_thriller_movies = db.query_all(QUERY_MYSTERY_AND_THRILLER_MOVIES, as: Video)
      romance_movies = db.query_all(QUERY_ROMANCE_MOVIES, as: Video)
      science_fiction_movies = db.query_all(QUERY_SCIENCE_FICTION_MOVIES, as: Video)

      POPULAR_MOVIES.set(popular_movies)
      POPULAR_TV.set(popular_tv)
      TOP_RATED_MOVIES.set(top_rated_movies)
      TOP_RATED_TV.set(top_rated_tv)
      ACTION_AND_ADVENTURE_MOVIES.set(action_and_adventure_movies)
      COMEDY_MOVIES.set(comedy_movies)
      DRAMA_MOVIES.set(drama_movies)
      FANTASY_MOVIES.set(fantasy_movies)
      HORROR_MOVIES.set(horror_movies)
      MILITARY_AND_WAR_MOVIES.set(military_and_war_movies)
      MYSTERY_AND_THRILLER_MOVIES.set(mystery_and_thriller_movies)
      ROMANCE_MOVIES.set(romance_movies)
      SCIENCE_FICTION_MOVIES.set(science_fiction_movies)

      sleep 15.minutes
      Fiber.yield
    end
  end
end
