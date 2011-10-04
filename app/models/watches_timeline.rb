require 'will_paginate/page_number'
require 'will_paginate/per_page'

# Paginated timeline of movies watched by users.
# Aggregates several users that have watched the same movie in a single page.
# Exposes methods to find out movie ratings by these users.
#
# Acts as a paginated Enumerable, in some things also like an Array.
class WatchesTimeline
  def self.collection
    User.collection['watched']
  end
  
  def self.create(selector = {})
    new collection.find(selector, :sort => :_id)
  end
  
  extend ActiveSupport::Memoizable
  include Enumerable
  
  attr_reader :current_page, :per_page
  
  def initialize(watched_cursor)
    @watched_cursor = watched_cursor
    @current_page = WillPaginate::PageNumber(1)
    @per_page = WillPaginate.per_page
  end
  
  def reverse
    @watched_cursor.sort([:_id, -1])
    self
  end
  
  def limit(num)
    @per_page = num.to_i
    self
  end
  
  def page(pagenum)
    @current_page = WillPaginate::PageNumber(pagenum.nil? ? 1 : pagenum)
    self
  end
  
  def each(&block)
    load_movies.each(&block)
  end
  
  def people_who_watched(movie)
    user_ids(:movie_id => movie.id).map { |id| people[id] }
  end
  
  def rating_for(movie, user)
    watches(movie_id: movie.id, user_id: user.id).first['liked']
  end
  
  def offset
    current_page.to_offset(per_page)
  end
  
  def size
    load_movies.count
  end
  memoize :size
  alias length size
  
  def empty?
    size.zero?
  end
  
  # FIXME: this sucks so much
  def total_entries
    @watched_cursor.rewind!
    @watched_cursor.map {|w| w['movie_id'] }.uniq.size
  end
  memoize :total_entries
  
  def total_pages
    (total_entries / per_page) + 1
  end
  
  private
  
  def watches(filters = nil)
    load_movies
    if filters
      @watches.select { |w| filters.all? {|k,v| w[k.to_s] == v } }
    else
      @watches
    end
  end
  
  def load_movies
    return @movies if defined? @movies
    done_page = 0
    movie_ids = []
    @watches  = []
    
    @watched_cursor.each do |watch|
      movie_id = watch['movie_id']
      unless movie_ids.include? movie_id
        if movie_ids.size == per_page
          if (done_page += 1) == current_page then break # we're done
          else
            # start filling in a fresh page
            movie_ids.clear
            @watches.clear
          end
        end
        movie_ids << movie_id
      end
      @watches << watch
    end
    
    @movies = Movie.find(movie_ids)
  end
  
  def user_ids(filters = nil)
    watches(filters).map {|w| w['user_id'] }.uniq
  end
  
  def people
    User.find(user_ids, fields: %w[username name]).index_by(&:id)
  end
  memoize :people
end