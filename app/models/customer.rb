# Copyright © Mapotempo, 2013-2016
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
require 'sanitize'
require 'json'

class Customer < ApplicationRecord
  default_scope { order(:id) }

  belongs_to :reseller
  belongs_to :profile
  belongs_to :router
  belongs_to :job_destination_geocoding, class_name: 'Delayed::Backend::ActiveRecord::Job', dependent: :destroy
  belongs_to :job_store_geocoding, class_name: 'Delayed::Backend::ActiveRecord::Job', dependent: :destroy
  belongs_to :job_optimizer, class_name: 'Delayed::Backend::ActiveRecord::Job', dependent: :destroy
  has_many :products, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :plannings, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :order_arrays, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :zonings, inverse_of: :customer, dependent: :delete_all
  before_destroy :destroy_disable_vehicle_usage_sets_validation # Declare and run before has_many :vehicle_usage_sets
  has_many :vehicle_usage_sets, inverse_of: :customer, autosave: true, dependent: :destroy
  has_many :vehicles, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :stores, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :destinations, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :tags, inverse_of: :customer, autosave: true, dependent: :delete_all
  has_many :users, inverse_of: :customer, dependent: :destroy
  has_many :deliverable_units, inverse_of: :customer, autosave: true, dependent: :delete_all, after_add: :update_deliverable_units_track, after_remove: :update_deliverable_units_track
  enum router_dimension: Router::DIMENSION

  attr_accessor :deliverable_units_updated, :device, :exclude_users

  include HashBoolAttr
  store_accessor :router_options, :time, :distance, :avoid_zones, :isochrone, :isodistance, :track, :motorway, :toll, :trailers, :weight, :weight_per_axle, :height, :width, :length, :hazardous_goods, :max_walk_distance, :approach, :snap, :strict_restriction
  hash_bool_attr :router_options, :time, :distance, :avoid_zones, :isochrone, :isodistance, :track, :motorway, :toll, :strict_restriction

  include LocalizedAttr # To use to_delocalized_decimal method

  nilify_blanks
  auto_strip_attributes :name, :print_header, :default_country

  include TimeAttr
  attribute :take_over, ScheduleType.new
  time_attr :take_over

  # We do not want to test if ref is uniq
  #validates :ref, uniqueness: { scope: :reseller_id, case_sensitive: true }, allow_nil: true, allow_blank: true
  validates :profile, presence: true
  validates :router, presence: true
  validates :router_dimension, presence: true
  validates :name, presence: true
  validates :default_country, presence: true
  validates :stores, length: { maximum: Mapotempo::Application.config.max_destinations / 10, message: :over_max_limit }
  validates :destinations, length: { maximum: Mapotempo::Application.config.max_destinations, message: :over_max_limit }
  validates :optimization_cluster_size, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_vehicles, numericality: { greater_than: 0 }
  validate do
    errors.add(:max_vehicles, :not_an_integer) if @invalid_max_vehicle
    !@invalid_max_vehicle
  end
  validates :speed_multiplicator, numericality: { greater_than_or_equal_to: 0.5, less_than_or_equal_to: 1.5 }, if: :speed_multiplicator

  after_initialize :assign_defaults, :update_max_vehicles, if: :new_record?
  after_initialize :assign_device
  after_create :create_default_store, :create_default_vehicle_usage_set, :create_default_deliverable_unit
  before_update :update_outdated, :update_max_vehicles, :update_enable_multi_visits
  before_save :sanitize_print_header, :nilify_router_options_blanks
  before_save :devices_update_vehicles, prepend: true
  before_validation :check_router_options_format

  include RefSanitizer

  scope :includes_deps, -> { includes([:profile, :router, :job_optimizer, :job_destination_geocoding, :job_store_geocoding, :users]) }
  scope :includes_stores, -> { includes(:stores) }

  amoeba do
    nullify :job_destination_geocoding_id
    nullify :job_store_geocoding_id
    nullify :job_optimizer_id
    nullify :ref

    # No duplication of OrderArray
    exclude_association :products
    exclude_association :order_arrays
    exclude_association :ref
    exclude_association :users, if: :exclude_users

    customize(lambda { |original, copy|
      def copy.assign_defaults; end

      def copy.update_max_vehicles; end

      def copy.create_default_store; end

      def copy.create_default_vehicle_usage_set; end

      def copy.create_default_deliverable_unit; end

      def copy.update_outdated; end

      def copy.update_enable_multi_visits; end

      def copy.sanitize_print_header; end

      def copy.devices_update_vehicles; end

      copy.save!(validate: false)

      deliverable_unit_ids_map = Hash[original.deliverable_units.map(&:id).zip(copy.deliverable_units)].merge(nil => nil)
      vehicles_map = Hash[original.vehicles.zip(copy.vehicles)].merge(nil => nil)
      vehicle_usage_sets_map = Hash[original.vehicle_usage_sets.zip(copy.vehicle_usage_sets)].merge(nil => nil)
      vehicle_usages_map = Hash[original.vehicle_usage_sets.collect(&:vehicle_usages).flatten.zip(copy.vehicle_usage_sets.collect(&:vehicle_usages).flatten)].merge(nil => nil)
      stores_map = Hash[original.stores.zip(copy.stores)].merge(nil => nil)
      visits_map = Hash[original.destinations.collect(&:visits).flatten.zip(copy.destinations.collect(&:visits).flatten)].merge(nil => nil)
      tags_map = Hash[original.tags.zip(copy.tags)].merge(nil => nil)
      zonings_map = Hash[original.zonings.zip(copy.zonings)].merge(nil => nil)

      copy.vehicles.each{ |vehicle|
        vehicle.capacities = Hash[vehicle.capacities.to_a.map{ |q| deliverable_unit_ids_map[q[0]] && [deliverable_unit_ids_map[q[0]].id, q[1]] }.compact]
        vehicle.save!(validate: false)
      }

      copy.vehicle_usage_sets.each{ |vehicle_usage_set|
        vehicle_usage_set.store_start = stores_map[vehicle_usage_set.store_start]
        vehicle_usage_set.store_stop = stores_map[vehicle_usage_set.store_stop]
        vehicle_usage_set.store_rest = stores_map[vehicle_usage_set.store_rest]

        vehicle_usage_set.vehicle_usages.each{ |vehicle_usage|
          vehicle_usage.vehicle = vehicles_map[vehicle_usage.vehicle]
          vehicle_usage.store_start = stores_map[vehicle_usage.store_start]
          vehicle_usage.store_stop = stores_map[vehicle_usage.store_stop]
          vehicle_usage.store_rest = stores_map[vehicle_usage.store_rest]
          vehicle_usage.save!(validate: false)
        }
        vehicle_usage_set.save!(validate: false)
      }

      copy.destinations.each{ |destination|
        destination.tags = destination.tags.collect{ |tag| tags_map[tag] }

        destination.visits.each{ |visit|
          visit.tags = visit.tags.collect{ |tag| tags_map[tag] }
          visit.quantities = Hash[visit.quantities.to_a.map{ |q| deliverable_unit_ids_map[q[0]] && [deliverable_unit_ids_map[q[0]].id, q[1]] }.compact]
          visit.save!(validate: false)
        }
        destination.save!(validate: false)
      }

      copy.zonings.each{ |zoning|
        zoning.zones.each{ |zone|
          zone.vehicle = vehicles_map[zone.vehicle]
          zone.save!(validate: false)
        }
      }

      copy.plannings.each{ |planning|
        planning.vehicle_usage_set = vehicle_usage_sets_map[planning.vehicle_usage_set]
        planning.zonings = planning.zonings.collect{ |zoning| zonings_map[zoning] }
        planning.tags = planning.tags.collect{ |tag| tags_map[tag] }

        # All routes must be caught in memory, don't use scopes
        planning.routes.each{ |route|
          route.vehicle_usage = vehicle_usages_map[route.vehicle_usage]

          route.stops.each{ |stop|
            stop.visit = visits_map[stop.visit]
            stop.save!(validate: false)
          }
          route.save!(validate: false)
        }
        planning.save!(validate: false)
      }

      copy.save!(validate: false)
      copy.reload
    })
  end

  def duplicate()
    Customer.transaction do
      copy = self.amoeba_dup
      copy.name += " (#{I18n.l(Time.zone.now, format: :long)})"
      copy.ref = copy.ref ? Time.new.to_i.to_s : nil
      copy.test = Mapotempo::Application.config.customer_test_default
      copy.save!(validate: false)
      copy
    end
  end

  def assign_device
    @device = Device.new(self)
  end

  def devices
    if self[:devices].respond_to?('deep_symbolize_keys!')
      self[:devices].deep_symbolize_keys!
    else
      self[:devices]
    end
  end

  def default_position
    store = stores.find{ |s| !s.lat.nil? && !s.lng.nil? }
    # store ? [store.lat, store.lng] : [I18n.t('stores.default.lat'), I18n.t('stores.default.lng')]
    {lat: store ? store.lat : I18n.t('stores.default.lat'), lng: store ? store.lng : I18n.t('stores.default.lng')}
  end

  def max_vehicles
    @max_vehicles ||= vehicles.size
  end

  def max_vehicles=(max)
    if !max.blank?
      @max_vehicles = Integer(max.to_s, 10)
    end
  rescue ArgumentError
    @invalid_max_vehicle = true
  end

  def visits
    destinations.collect(&:visits).flatten
  end

  def delete_all_destinations
    destinations.delete_all
    Route.includes_stops.scoping do
      plannings.reload.each { |p|
        p.routes.each do |route|
          # reindex remaining stops (like rests)
          route.force_reindex
          route.outdated = true if !route.geojson_points.try(&:empty?) || !route.geojson_tracks.try(&:empty?)
        end
        p.save!
      }
    end
  end

  def too_many_plannings?
    if !Rails.configuration.plannings_limitation.nil?
      Rails.configuration.plannings_limitation < self.plannings.length
    else
      false
    end
  end

  private

  def devices_update_vehicles
    # Remove device association on vehicles if devices credentials have changed
    Mapotempo::Application.config.devices.to_h.each{ |device_name, device_object|
      if device_object.respond_to?('definition')
        device_definition = device_object.definition
        if device_definition.key?(:forms) && device_definition[:forms].key?(:settings) && device_definition[:forms].key?(:vehicle)
          device_definition[:forms][:vehicle].keys.each{ |key|
            self.vehicles.select(&:devices).each{ |vehicle| vehicle.devices[key] = nil } if self.send("#{device_name}_changed?")
          }
        end
      end
    }
  end

  Mapotempo::Application.config.devices.to_h.each{ |device_name, device_object|
    if device_object.respond_to?('definition')
      device_definition = device_object.definition
      if device_definition.key?(:forms) && device_definition[:forms].key?(:settings)

        define_method("#{device_name}_changed?") do
          before = self.changed.include?('devices') ? self.changes[:devices].first : nil
          after = self.changed.include?('devices') ? self.changes[:devices].second : nil

          if self.changed.include?('devices') && !before.nil? && !after.nil?
            if after.include?(device_name) && before.include?(device_name)
              device_definition[:forms][:settings].keys.each{ |key|
                return true if after[device_name][key] != before[device_name][key]
              }
            end
          end

          false
        end

      end
    end
  }

  def assign_defaults
    self.default_country ||= I18n.t('customers.default.country')
    self.enable_references = Mapotempo::Application.config.enable_references
    self.enable_multi_visits = Mapotempo::Application.config.enable_multi_visits
  end

  def create_default_store
    stores.create(
      name: I18n.t('stores.default.name'),
      city: I18n.t('stores.default.city'),
      lat: Float(I18n.t('stores.default.lat')),
      lng: Float(I18n.t('stores.default.lng'))
    )
  end

  def create_default_vehicle_usage_set
    vehicle_usage_sets.create(
      name: I18n.t('vehicle_usage_sets.default.name'),
      store_start: stores[0],
      store_stop: stores[0]
    )
  end

  def create_default_deliverable_unit
    deliverable_units.create(
      default_quantity: 1
    )
  end

  def update_outdated
    if take_over_changed? || router_id_changed? || router_dimension_changed? || router_options_changed? || speed_multiplicator_changed? || @deliverable_units_updated
      Route.transaction do
        plannings.each{ |planning|
          planning.routes.each{ |route|
            route.outdated = true
          }
        }
      end
    end
  end

  def update_deliverable_units_track(_deliverable_unit)
    @deliverable_units_updated = true
  end

  def update_max_vehicles
    if max_vehicles != vehicles.size
      if vehicles.size < max_vehicles
        # Add new
        (max_vehicles - vehicles.size).times{ |_i|
          vehicle = vehicles.build(name: I18n.t('vehicles.default_name', n: vehicles.size + 1))
          vehicle.color = COLORS_TABLE[(vehicles.size - 1) % COLORS_TABLE.size]
        }
      elsif vehicles.size > max_vehicles
        # Delete
        (vehicles.size - max_vehicles).times{ |_i|
          vehicle = vehicles[vehicles.size - 1]
          vehicles.destroy(vehicle)
        }
      end
      @max_vehicles = vehicles.size
    end
  end

  def update_enable_multi_visits
    if enable_multi_visits_changed?
      Destination.transaction do
        if enable_multi_visits
          self.destinations.each{ |destination|
            destination.visits.each{ |visit|
              visit.ref = destination.ref
              visit.tags = destination.tags # ?
            }
            destination.ref = nil
            destination.tag_ids = []
          }
        else
          self.destinations.each{ |destination|
            if !destination.visits.empty?
              destination.ref = destination.visits[0].ref
              destination.tags = destination.visits[0].tags # ?
              destination.visits.each{ |visit|
                visit.ref = nil
                visit.tag_ids = []
              }
            end
          }
        end
      end
    end
  end

  def sanitize_print_header
    self.print_header = Sanitize.fragment(print_header, Sanitize::Config::RELAXED)
  end

  def nilify_router_options_blanks
    true_options = router.options.select { |_, v| v == 'true' }.keys
    write_attribute :router_options, self.router_options.delete_if { |k, v| v.to_s.empty? || true_options.exclude?(k) }
  end

  def destroy_disable_vehicle_usage_sets_validation
    vehicle_usage_sets.each{ |vehicle_usage_set|
      def vehicle_usage_set.destroy_vehicle_usage_set
        # Avoid validation of at least one vehicle_usage_set by customer
      end
    }
  end

  def check_router_options_format
    self.router_options.each do |k, v|
      if k == 'distance' || k == 'weight' || k == 'weight_per_axle' || k == 'height' || k == 'width' || k == 'length' || k == 'max_walk_distance'
        self.router_options[k] = Customer.to_delocalized_decimal(v) if v.is_a?(String)
      end
    end
  end
end
