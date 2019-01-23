# Copyright © Mapotempo, 2016
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
module SharedParams
  extend Grape::API::Helpers

  params :params_from_entity do |options|
    options[:entity].each{ |k, d|
      v = d.dup # Important: use dup not to modify original entity
      v[:type] = Boolean if v[:type] == 'Boolean'
      # To be homogeneous with rails and avoid timezone problems, need to use Time instead of DateTime
      if v[:type] == DateTime
        v[:type] = Time
        v[:coerce_with] = ->(val) { val.is_a?(String) ? Time.parse(val + ' UTC') : val }
      end
      if v[:values]
        classes = v[:values].map(&:class).uniq
        v[:type] = classes[0] if classes.size == 1 && v[:type] != classes[0]
      end
      v[:type] = Array[v[:type]] if v.key?(:is_array)
      send(v[:required] ? :requires : :optional, k, v.except(:required, :is_array, :param_type))
    }
  end

  ID_DESC = 'Id or the ref field value, then use "ref:[value]".'.freeze

end

