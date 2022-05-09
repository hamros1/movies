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

module GetAMovie::Routing
  macro get(path, controller, method = :handle)
    get {{ path }} do |env|
      controller_instance = {{ controller }}.new
      controller_instance.{{ method.id }}(env)
    end
  end

  macro post(path, controller, method = :handle)
    post {{ path }} do |env|
      controller_instance = {{ controller }}.new
      controller_instance.{{ method.id }}(env)
    end
  end

  macro ws(path, controller, method = :handle)
    ws {{ path }} do |socket|
      controller_instance = {{ controller }}.new
      controller_instance.{{ method.id }}(socket)
    end
  end
end
