json.planning_id stop.route.planning_id
json.route_id stop.route_id
json.stop_id stop.id
json.destination true

if stop.route.vehicle_usage_id
  json.vehicle_name stop.route.vehicle_usage.vehicle.name
else
  json.automatic_insert true
end

(json.error true) if (stop.is_a?(StopVisit) && !stop.position?) || stop.out_of_window || stop.out_of_capacity || stop.out_of_drive_time || stop.no_path

json.extract! stop, :name, :street, :detail, :postalcode, :city, :country, :comment, :phone_number, :lat, :lng, :drive_time, :out_of_window, :out_of_capacity, :out_of_drive_time, :no_path, :active
json.ref stop.ref if stop.route.planning.customer.enable_references
json.open_close1 stop.open1 || stop.close1
(json.open1 stop.open1_time) if stop.open1
(json.open1_day number_of_days(stop.open1)) if stop.open1
(json.close1 stop.close1_time) if stop.close1
(json.close1_day number_of_days(stop.close1)) if stop.close1
json.open_close2 stop.open2 || stop.close2
(json.open2 stop.open2_time) if stop.open2
(json.open2_day number_of_days(stop.open2)) if stop.open2
(json.close2 stop.close2_time) if stop.close2
(json.close2_day number_of_days(stop.close2)) if stop.close2
(json.wait_time '%i:%02i' % [stop.wait_time / 60 / 60, stop.wait_time / 60 % 60]) if stop.wait_time && stop.wait_time > 60
(json.time stop.time_time) if stop.time
(json.time_day number_of_days(stop.time)) if stop.time
(json.link_phone_number current_user.link_phone_number) if current_user.url_click2call
json.distance (stop.distance || 0) / 1000
duration = nil
if stop.is_a?(StopVisit)
  json.visits true
  visit = stop.visit
  json.visit_id visit.id
  json.destination_id visit.destination.id
  json.color stop.default_color
  json.index_visit (visit.destination.visits.index(visit) + 1) if visit.destination.visits.size > 1
  tags = visit.destination.tags | visit.tags
  if !tags.empty?
    json.tags_present do
      json.tags do
        json.array! tags, :label
      end
    end
  end
  if stop.route.planning.customer.enable_orders
    order = stop.order
    if order
      json.orders order.products.collect(&:code).join(', ')
    end
  else
    json.quantities visit_quantities(visit, stop.route.vehicle_usage && stop.route.vehicle_usage.vehicle) do |units|
      json.quantity units[:quantity] if units[:quantity]
      json.unit_icon units[:unit_icon]
    end
  end
  if stop.status
    json.status t("plannings.edit.stop_status.#{stop.status.downcase}", default: stop.status)
    json.status_code stop.status.downcase
  end
  if stop.route.last_sent_to && stop.status && stop.eta
    (json.eta_formated l(stop.eta, format: :hour_minute)) if stop.eta
  end
  duration = visit.default_take_over_time_with_seconds
  if @show_isoline && stop.route.vehicle_usage_id
    json.vehicle_usage_id stop.route.vehicle_usage_id
    json.isoline stop.route.vehicle_usage.vehicle.default_router.isochrone || stop.route.vehicle_usage.vehicle.default_router.isodistance
    json.isochrone stop.route.vehicle_usage.vehicle.default_router.isochrone
    json.isodistance stop.route.vehicle_usage.vehicle.default_router.isodistance
  end
elsif stop.is_a?(StopRest)
  json.rest do
    json.rest true
    duration = stop.route.vehicle_usage.default_rest_duration_time_with_seconds
    (json.store_id stop.route.vehicle_usage.default_store_rest.id) if stop.route.vehicle_usage.default_store_rest
    (json.error true) if stop.route.vehicle_usage.default_store_rest && !stop.route.vehicle_usage.default_store_rest.position?
  end
end
json.duration duration if duration
