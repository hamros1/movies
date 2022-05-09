# This file is a component in the Rosencrantz Entertainment Conglomerate
# Copyright (C) 2021 Hampus Andreas Niklas Rosencrantz

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

class GetAMovie::Routes::Search < GetAMovie::Routes::BaseRoute
  def results(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    query = env.params.query["search_query"]?
    query ||= env.params.query["q"]?

    page = env.params.query["page"]

    if query && !query.empty?
      if page && !page.empty?
        env.redirect "/search?q=" + URI.encode_www_form(query) + "&page=" + page
      else
        env.redirect "/search?q=" + URI.encode_www_form(query)
      end
    else
      env.redirect "/search"
    end
  end

  def search(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    query = env.params.query["search_query"]?
    query ||= env.params.query["q"]?

    if !query || query.empty?
      env.set "search", ""
    else
      page = env.params.query["page"]?.try &.to_i?
      page ||= 1

      user = env.get? "user"

      begin
        search_query, count, videos, operators = process_search_query(query, page, user)
      rescue ex
        return error_template(500, ex)
      end

      operator_hash = {} of String => String
      operators.each do |operator|
        key, value = operator.downcase.split(":")
        operator_hash[key] = value
      end

      env.set "search", query
      templated "search"
    end
  end
end
