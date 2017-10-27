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
class DeliverableUnitQuantity
  def self.dump(quantities)
    hash = quantities.is_a?(Hash) ? quantities : quantities.attributes
    hash = hash.delete_if{ |k, v|
      !v
    }
    hash.size > 0 ? hash : nil
  end

  def self.load(quantities)
    new(quantities)
  end

  def initialize(quantities)
    @quantities = quantities ? Hash[quantities.map{ |k, v|
      if v && !v.empty?
        # float value will be validated by the model
        value = Float(v) rescue v
        [Integer(k), value]
      else
        nil
      end
    }.compact] : {}
  end

  def attributes
    @quantities
  end

  def ==(other)
    @quantities == other.attributes
  end

  def to_s
    @quantities.to_s
  end

  def method_missing(method_sym, *arguments, &block)
    @quantities.send(method_sym, *arguments, &block)
  end
end
