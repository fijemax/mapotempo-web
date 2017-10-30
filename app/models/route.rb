# Copyright © Mapotempo, 2013-2017
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
class Route < ApplicationRecord
  COLOR_DEFAULT = '#707070'.freeze

  belongs_to :planning
  belongs_to :vehicle_usage
  has_many :stops, inverse_of: :route, autosave: true, dependent: :delete_all, after_add: :update_stops_track, after_remove: :update_stops_track
  serialize :quantities, DeliverableUnitQuantity

  nilify_blanks
  validates :planning, presence: true
#  validates :vehicle_usage, presence: true # nil on unplanned route
  validate :stop_index_validation
  attr_accessor :no_stop_index_validation, :vehicle_color_changed

  include TimeAttr
  attribute :start, ScheduleType.new
  attribute :end, ScheduleType.new
  time_attr :start, :end

  before_update :update_vehicle_usage, :update_geojson

  after_initialize :assign_defaults, if: 'new_record?'
  after_create :complete_geojson

  scope :for_customer_id, ->(customer_id) { joins(:planning).where(plannings: {customer_id: customer_id}) }
  scope :includes_vehicle_usages, -> { includes({vehicle_usage: [:vehicle_usage_set, :vehicle]}) }
  scope :includes_stops, -> { includes(:stops) }
  # The second visit is for counting the visit index from all the visits of the destination
  scope :includes_destinations, -> { includes({stops: {visit: [:tags, {destination: [:visits, :tags, :customer]}]}}) }

  include RefSanitizer

  amoeba do
    enable

    customize(lambda { |original, copy|
      def copy.update_vehicle_usage; end

      def copy.assign_defaults; end

      copy.planning = original.planning
      copy.stops.each{ |stop|
        stop.route = copy
      }
    })
  end

  def init_stops(compute = true, ignore_errors = false)
    stops.clear
    if vehicle_usage && vehicle_usage.default_rest_duration
      stops.build(type: StopRest.name, active: true, index: 1)
    end

    compute!(ignore_errors: ignore_errors) if compute
  end

  def default_stops
    i = stops.size
    planning.visits_compatibles.each { |visit|
      stops.build(type: StopVisit.name, visit: visit, active: true, index: i += 1)
    }
    self.outdated = true
  end

  def service_time_start_value
    vehicle_usage.default_service_time_start if vehicle_usage && vehicle_usage.default_service_time_start
  end

  def service_time_end_value
    vehicle_usage.default_service_time_end if vehicle_usage && vehicle_usage.default_service_time_end
  end

  def plan(departure = nil, options = {})
    options[:ignore_errors] = false if options[:ignore_errors].nil?

    self.touch if self.id # To force route save in case none attribute has changed below
    self.distance = 0
    geojson_tracks = []

    self.stop_distance = 0
    self.stop_no_path = false
    self.stop_out_of_drive_time = nil
    self.emission = 0
    self.start = self.end = nil
    last_lat, last_lng = nil, nil
    if vehicle_usage && !stops.empty?
      service_time_start = service_time_start_value
      service_time_end = service_time_end_value
      self.end = self.start = departure || vehicle_usage.default_open
      speed_multiplicator = vehicle_usage.vehicle.default_speed_multiplicator
      if vehicle_usage.default_store_start.try(&:position?)
        last_lat, last_lng = vehicle_usage.default_store_start.lat, vehicle_usage.default_store_start.lng
      end
      router = vehicle_usage.vehicle.default_router
      router_dimension = vehicle_usage.vehicle.default_router_dimension
      stops_drive_time = {}

      # Add service time
      unless service_time_start.nil?
        self.end += service_time_start
      end

      stops_sort = stops.sort_by(&:index)

      # Collect route legs
      segments = stops_sort.select{ |stop|
        stop.active && (stop.position? || (stop.is_a?(StopRest) && ((stop.open1 && stop.close1) || (stop.open2 && stop.close2)) && stop.duration))
      }.collect{ |stop|
        if stop.position?
          ret = [last_lat, last_lng, stop.lat, stop.lng] if !last_lat.nil? && !last_lng.nil?
          last_lat, last_lng = stop.lat, stop.lng
        end
        ret
      }

      if !last_lat.nil? && !last_lng.nil? && vehicle_usage.default_store_stop.try(&:position?)
        segments << [last_lat, last_lng, vehicle_usage.default_store_stop.lat, vehicle_usage.default_store_stop.lng]
      else
        segments << nil
      end

      # Compute legs traces
      begin
        router_options = vehicle_usage.vehicle.default_router_options.symbolize_keys.merge(speed_multiplicator_areas: Zoning.speed_multiplicator_areas(planning.zonings))

        ts = router.trace_batch(speed_multiplicator, segments.reject(&:nil?), router_dimension, router_options)
        traces = segments.collect{ |segment|
          if segment.nil?
            [nil, nil, nil]
          else
            (ts && !ts.empty? && ts.shift) || [nil, nil, nil]
          end
        }
      rescue RouterError
        raise unless options[:ignore_errors]
        traces = [nil, nil, nil] * segments.size
      end
      traces[0] = [0, 0, nil] unless vehicle_usage.default_store_start.try(&:position?)

      # Recompute Stops
      stops_time_windows = {}
      quantities_ = {}
      previous_with_pos = vehicle_usage.default_store_start.try(:position?)
      stops_sort.each{ |stop|
        if stop.active && (stop.position? || (stop.is_a?(StopRest) && ((stop.open1 && stop.close1) || (stop.open2 && stop.close2)) && stop.duration))
          stop.distance, stop.drive_time, trace = traces.shift
          stop.no_path = previous_with_pos && stop.position? && trace.nil?
          previous_with_pos = stop if stop.position?

          if trace && !options[:no_geojson]
            geojson_tracks << {
              type: 'Feature',
              geometry: {
                type: 'LineString',
                polylines: trace,
              },
              properties: {
                route_id: self.id,
                color: self.default_color,
                drive_time: stop.drive_time,
                distance: stop.distance
              }.compact
            }.to_json
          end

          if stop.drive_time
            stops_drive_time[stop] = stop.drive_time
            stop.time = self.end + stop.drive_time
          elsif stop.is_a?(StopRest) || self.end
            stop.time = self.end
          else
            stop.time = nil
          end

          if stop.time
            open, close, late_wait = stop.best_open_close(stop.time)
            stops_time_windows[stop] = [open, close]
            if open && stop.time < open
              stop.wait_time = open - stop.time
              stop.time = open
            else
              stop.wait_time = nil
            end
            stop.out_of_window = !!(late_wait && late_wait > 0)

            self.distance += stop.distance if stop.distance
            self.end = stop.time + stop.duration

            if stop.visit.try(:default_quantities?)
              unless options[:no_quantities]
                stop.route.planning.customer.deliverable_units.each{ |du|
                  quantities_[du.id] = (quantities_[du.id] || 0) + (stop.visit.default_quantities[du.id] || 0)
                }
                stop.out_of_capacity = stop.route.planning.customer.deliverable_units.any?{ |du|
                  (vehicle_usage.vehicle.default_capacities[du.id] && quantities_[du.id] > vehicle_usage.vehicle.default_capacities[du.id]) ||
                    quantities_[du.id] < 0 # FIXME with initial quantity
                }
              end
            else
              stop.out_of_capacity = false
            end

            stop.out_of_drive_time = stop.time > vehicle_usage.default_close
          end
        else
          stop.active = stop.out_of_capacity = stop.out_of_drive_time = stop.out_of_window = stop.no_path = false
          stop.distance = stop.time = stop.wait_time = nil
        end
      }

      unless options[:no_quantities]
        self.quantities = quantities_.each{ |k, v|
          v = v.round(3)
        }
      end

      # Last stop to store
      distance, drive_time, trace = traces.shift
      if drive_time
        self.distance += distance
        stops_drive_time[:stop] = drive_time
        self.end += drive_time
        self.stop_distance, self.stop_drive_time = distance, drive_time
      end
      self.stop_no_path = vehicle_usage.default_store_stop.try(:position?) && stops_sort.any?{ |s| s.active && s.position? } && trace.nil?

      # Add service time to end point
      self.end += service_time_end unless service_time_end.nil?

      if trace && !options[:no_geojson]
        geojson_tracks << {
          type: 'Feature',
          geometry: {
            type: 'LineString',
            polylines: trace,
          },
          properties: {
            route_id: self.id,
            color: self.default_color,
            drive_time: self.stop_drive_time,
            distance: self.stop_distance
          }.compact
        }.to_json
      end

      self.geojson_tracks = geojson_tracks unless options[:no_geojson]
      self.stop_out_of_drive_time = self.end > vehicle_usage.default_close
      self.emission = vehicle_usage.vehicle.emission.nil? || vehicle_usage.vehicle.consumption.nil? ? nil : self.distance / 1000 * vehicle_usage.vehicle.emission * vehicle_usage.vehicle.consumption / 100

      [stops_sort, stops_drive_time, stops_time_windows]
    end
  end

  # Available options:
  # ignore_errors
  # no_geojson
  # no_quantities
  def compute!(options = {})
    if self.vehicle_usage
      self.geojson_tracks = nil
      stops_sort, stops_drive_time, stops_time_windows = plan(nil, options)

      if stops_sort
        # Try to minimize waiting time by a later begin
        time = self.end
        time -= stops_drive_time[:stop] if stops_drive_time[:stop]
        time -= vehicle_usage.default_service_time_end if vehicle_usage.default_service_time_end
        stops_sort.reverse_each{ |stop|
          if stop.active && (stop.position? || stop.is_a?(StopRest))
            _open, close = stops_time_windows[stop]
            if stop.time && (stop.out_of_window || (close && time > close))
              time = [stop.time, close ? close - stop.duration : 0].max
            else
              # Latest departure time
              time = [time, close].min if close

              # New arrival stop time
              time -= stop.duration
            end

            # Previous departure time
            time -= stops_drive_time[stop] if stops_drive_time[stop]
          end
        }

        time -= vehicle_usage.default_service_time_start if vehicle_usage.default_service_time_start

        force_start = planning.customer.optimization_force_start.nil? ? Mapotempo::Application.config.optimize_force_start : planning.customer.optimization_force_start
        if time > start && !force_start
          # We can sleep a bit more on morning, shift departure
          plan(time, options)
        end
      end
    else
      unless options[:no_quantities]
        self.quantities = compute_quantities.each{ |_, v|
          v = v.round(3)
        }
      end
    end

    self.geojson_points = stops_to_geojson_points unless options[:no_geojson]

    self.outdated = false
    true
  end

  def compute(options = {})
    compute!(options) if self.outdated
    true
  end

  def set_visits(visits, recompute = true, ignore_errors = false)
    Stop.transaction do
      init_stops false
      add_visits visits, recompute, ignore_errors
    end
  end

  def add_visits(visits, recompute = true, ignore_errors = false)
    Stop.transaction do
      i = stops.size
      visits.each{ |stop|
        visit, active = stop
        stops.build(type: StopVisit.name, visit: visit, active: active, index: i += 1)
      }
      self.outdated = true

      compute(ignore_errors: ignore_errors) if recompute
    end
  end

  def add(visit, index = nil, active = false, stop_id = nil)
    index = stops.size + 1 if !index || index < 0
    shift_index(index)
    stops.build(type: StopVisit.name, visit: visit, index: index, active: active, id: stop_id)
    self.outdated = true
  end

  def add_rest(active = true, stop_id = nil)
    index = stops.size + 1
    stops.build(type: StopRest.name, index: index, active: active, id: stop_id)
    self.outdated = true
  end

  def add_or_update_rest(active = true, stop_id = nil)
    if !stops.find{ |stop| stop.is_a?(StopRest) }
      add_rest(active, stop_id)
    end
    self.outdated = true
  end

  def remove_visit(visit)
    stops.each{ |stop|
      if stop.is_a?(StopVisit) && stop.visit == visit
        remove_stop(stop)
      end
    }
  end

  def remove_stop(stop)
    shift_index(stop.index + 1, -1)
    self.outdated = true
    stops.destroy(stop)
  end

  def move_stop(stop, index)
    index = stops.size if index < 0
    if stop.index
      if index < stop.index
        shift_index(index, 1, stop.index - 1)
      else
        shift_index(stop.index + 1, -1, index)
      end
      stop.index = index
    end
    self.outdated = true
  end

  def move_stop_out(stop, force = false)
    if force || stop.is_a?(StopVisit)
      shift_index(stop.index + 1, -1)
      stop.route.stops.destroy(stop)
      self.outdated = true
    end
  end

  def force_reindex
    # Force reindex after customers.destination.destroy_all
    stops.sort_by(&:index).each_with_index{ |stop, index|
      stop.index = index + 1
    }
  end

  def sum_out_of_window
    stops.to_a.sum{ |stop|
      if stop.time
        open, close = stop.best_open_close(stop.time)
        (open && stop.time < open ? open - stop.time : 0) + (close && stop.time > close ? stop.time - close : 0)
      else
        0
      end
    }
  end

  def active(action)
    stops.each{ |stop|
      if [:reverse, :all, :none].include?(action)
        stop.active = action == :reverse ? !stop.active : action == :all
      elsif [:status_any, :status_none].include?(action)
        stop.active = action == :status_none ? stop.status.nil? : !!stop.status
      else
        stop.active = stop.status && stop.status.downcase == action.to_s
      end
    }
    self.outdated = true
    true
  end

  def size_active
    vehicle_usage_id ? (stops.loaded? ? stops.select(&:active).size : stops.where(active: true).count) : 0
  end

  def no_geolocalization
    stops.loaded? ?
      stops.any?{ |s| s.is_a?(StopVisit) && !s.position? } :
      stops.joins(visit: :destination).where('destinations.lat IS NULL AND destinations.lng IS NULL').count > 0
  end

  def no_path
    vehicle_usage_id && (stop_no_path ||
      (stops.loaded? ?
        stops.any?{ |s| s.is_a?(StopVisit) && s.no_path } :
        stops.select(:no_path).where(type: 'StopVisit', no_path: true).count > 0))
  end

  [:out_of_window, :out_of_capacity, :out_of_drive_time].each do |s|
    define_method "#{s}" do
      vehicle_usage_id && (respond_to?("stop_#{s}") && send("stop_#{s}") ||
        if stops.loaded?
          stops.any?(&s)
        else
          h = {}
          h[s] = true
          stops.select(s).where(h).count > 0
        end)
    end
  end

  include LocalizedAttr

  attr_localized :quantities

  # required for migration
  def compute_quantities
    Hash[planning.customer.deliverable_units.map{ |du|
      [du.id, stops.to_a.sum(0) { |stop|
        stop.is_a?(StopVisit) && (stop.active || !vehicle_usage) ? (stop.visit.default_quantities[du.id] || 0) : 0
      }]
    }]
  end

  def reverse_order
    stops.sort_by{ |stop| -stop.index }.each_with_index{ |stop, index|
      stop.index = index + 1
    }
    self.outdated = true
  end

  def stops_segregate(active_only = true)
    stops.group_by{ |stop| (!active_only ? true : stop.active) && (stop.position? || stop.is_a?(StopRest)) }
  end

  def outdated=(value)
    if vehicle_usage && value
      self.optimized_at = nil unless optimized_at_changed?
      self.last_sent_to = self.last_sent_at = nil
    end
    self['outdated'] = value
  end

  def changed?
    @stops_updated || @vehicle_color_changed || super
  end

  def set_send_to(name)
    self.last_sent_to = name
    self.last_sent_at = Time.now.utc
  end

  def clear_sent_to
    self.last_sent_to = self.last_sent_at = nil
  end

  def default_color
    self.color || (self.vehicle_usage && self.vehicle_usage.vehicle.color) || COLOR_DEFAULT
  end

  def to_s
    "#{ref}:#{vehicle_usage && vehicle_usage.vehicle.name}=>[" + stops.collect(&:to_s).join(', ') + ']'
  end

  def self.routes_to_geojson(routes, include_stores = true, respect_hidden = true, include_linestrings = :polyline, with_quantities = false)
    stores_geojson = []

    if include_stores
      stores_geojson = routes.select { |r| r.vehicle_usage && (!respect_hidden || !r.hidden) }.map(&:vehicle_usage).flat_map { |vu| [vu.default_store_start, vu.default_store_stop, vu.default_store_rest] }.compact.uniq.select(&:position?).map do |store|
        coordinates = [store.lng, store.lat]
        {
          type: 'Feature',
          geometry: {
            type: 'Point',
            coordinates: coordinates
          },
          properties: {
            store_id: store.id,
            color: store.color,
            icon: store.icon,
            icon_size: store.icon_size
          }
        }.to_json unless coordinates.empty?
      end.compact
    end

    features = routes.select { |r| !respect_hidden || !r.hidden }.flat_map { |r|
      (include_linestrings && r.geojson_tracks || []) +
        ((with_quantities ? r.stops_to_geojson_points(with_quantities: true) : r.geojson_points) || []).compact
    }.compact
    features += stores_geojson unless stores_geojson.empty?

    if include_linestrings == true
      features = features.map { |feature|
        feature = JSON.parse(feature)
        if feature['geometry'] && feature['geometry']['polylines']
          feature['geometry']['coordinates'] = Polylines::Decoder.decode_polyline(feature['geometry'].delete('polylines'), 1e6).map { |a, b| [b.round(6), a.round(6)] }
        end
        feature.to_json
      }
    end

    '{"type":"FeatureCollection","features":[' + features.join(',') + ']}'
  end

  def to_geojson(include_stores = true, respect_hidden = true, include_linestrings = :polyline, with_quantities = false)
    self.class.routes_to_geojson([self], include_stores, respect_hidden, include_linestrings, with_quantities)
  end

  # Add route_id to geojson after create
  def complete_geojson
    self.geojson_tracks = self.geojson_tracks && self.geojson_tracks.map{ |s|
      linestring = JSON.parse(s)
      linestring['properties']['route_id'] = self.id
      linestring.to_json
    }
    self.geojson_points = self.geojson_points && self.geojson_points.map{ |s|
      point = JSON.parse(s)
      point['properties']['route_id'] = self.id
      point.to_json
    }
    self.update_columns(attributes.slice('geojson_tracks', 'geojson_points'))
  end

  def stops_to_geojson_points(options = {})
    unless stops.empty?
      inactive_stops = 0
      stops.sort_by(&:index).map do |stop|
        inactive_stops += 1 unless stop.active
        if stop.position?
          feat = {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [stop.lng, stop.lat]
            },
            properties: {
              route_id: self.id,
              index: stop.index,
              active: stop.active,
              number: vehicle_usage ? stop.number(inactive_stops) : nil,
              color: stop.default_color,
              icon: stop.icon,
              icon_size: stop.icon_size
            }
          }
          feat[:properties][:quantities] = stop.visit.default_quantities.map { |k, v|
            {
              deliverable_unit_id: k,
              quantity: v
            }
          } if options[:with_quantities] && stop.is_a?(StopVisit)
          feat.to_json
        end
      end.compact
    end
  end

  private

  def assign_defaults
    self.hidden = false
    self.locked = false
  end

  def shift_index(from, by = 1, to = nil)
    stops.partition{ |stop|
      stop.index < from || (to && stop.index > to)
    }[1].each{ |stop|
      stop.index += by
    }
  end

  def stop_index_validation
    if !@no_stop_index_validation && @stops_updated && !stops.empty? && stops.collect(&:index).sum != (stops.length * (stops.length + 1)) / 2
      bad_index = nil
      (1..stops.length).each{ |index|
        if stops[0..(index - 1)].collect(&:index).sum != (index * (index + 1)) / 2
          bad_index = index
          break
        end
      }
      route_name = vehicle_usage ? "#{ref}:#{vehicle_usage && vehicle_usage.vehicle.name}" : I18n.t('activerecord.attributes.planning.out_of_route')
      errors.add :stops, -> { I18n.t('activerecord.errors.models.route.attributes.stops.bad_index', index: bad_index || '', route: route_name) }
    end
    @no_stop_index_validation = nil
  end

  def update_stops_track(_stop)
    self.outdated = true unless new_record?
    @stops_updated = true
  end

  # When route is created, rest is already set in init_stops
  def update_vehicle_usage
    if vehicle_usage_id_changed?
      if vehicle_usage.default_rest_duration.nil?
        stops.select{ |stop| stop.is_a?(StopRest) }.each{ |stop|
          remove_stop(stop)
        }
      elsif stops.none?{ |stop| stop.is_a?(StopRest) }
        add_rest
      end
      self.outdated = true
    end
  end

  # Update geojson without need of computing route
  def update_geojson
    if color_changed? || @vehicle_color_changed
      self.geojson_tracks = self.geojson_tracks && self.geojson_tracks.map{ |s|
        linestring = JSON.parse(s)
        linestring['properties']['color'] = self.default_color
        linestring.to_json
      }
      self.geojson_points = stops_to_geojson_points
    end
  end
end
