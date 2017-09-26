// Copyright © Mapotempo, 2013-2017
//
// This file is part of Mapotempo.
//
// Mapotempo is free software. You can redistribute it and/or
// modify since you respect the terms of the GNU Affero General
// Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.
//
// Mapotempo is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Mapotempo. If not, see:
// <http://www.gnu.org/licenses/agpl.html>
//
'use strict';
var getPlanningsId = function() {
  return $.makeArray($('#plannings input[type=checkbox]:checked').map(function(index, id){ return $(id).val(); }));
};

var iCalendarExport = function(planningId) {
  var url = $('#ical_export').attr('href'), ids;
  // Initialize data only for index
  $('#btn-export').click(function(e) {
    ids = getPlanningsId();
    if (ids.length == 0) {
      warning(I18n.t('plannings.index.export.none_planning'));
      e.preventDefault();
    }
    $('#ical_export').attr('href', url + '&ids=' + ids.join(','));
  });

  $('.icalendar_email').click(function(e) {
    e.preventDefault();
    var ajaxParams = {email: true};
    if (!planningId) {
      ids = getPlanningsId();
      if (ids.length == 0) {
        warning(I18n.t('plannings.index.export.none_planning'));
        return;
      }
      else
        ajaxParams.ids = ids.join(',');
    }
    $.ajax({
      url: $(e.target).attr('href'),
      type: 'GET',
      data: ajaxParams,
      dataType: 'json'
    }).done(function() {
      notice(I18n.t('plannings.edit.export.icalendar.success'));
    }).fail(function() {
      stickyError(I18n.t('plannings.edit.export.icalendar.fail'));
    });
  });
};

var spreadsheetModalExport = function(columns, planningId) {
  $('#planning-spreadsheet-modal').on('show.bs.modal', function() {
    if ($('[name=spreadsheet-route]').val())
      $('[name=spreadsheet-out-of-route]').parent().parent().hide();
    else
      $('[name=spreadsheet-out-of-route]').parent().parent().show();
  });
  if (localStorage.spreadsheetStops) {
    $.each($('.spreadsheet-stops'), function(i, cb) {
      $(cb).prop('checked', localStorage.spreadsheetStops.split('|').indexOf($(cb).val()) >= 0);
    });
  }
  $('.columns-export-list').sortable({
    connectWith: '#spreadsheet-columns .ui-sortable'
  });
  var columnsExport = columns;
  var columnsSkip = localStorage.spreadsheetColumnsSkip && localStorage.spreadsheetColumnsSkip.split('|');
  if (localStorage.spreadsheetColumnsExport) {
    columnsExport = localStorage.spreadsheetColumnsExport.split('|');
    $.each(columns, function(i, c) {
      if (columnsExport.indexOf(c) < 0 && (!columnsSkip || columnsSkip.indexOf(c) < 0))
        columnsExport.push(c);
    });
  }
  var appendElement = function(parentSel, columnKey) {
    var displayName;
    var match = columnKey.match(new RegExp('^(.+)\\[(.*)\\]$'));
    if (match) {
      var export_translation = 'plannings.export_file.' + match[1];
      displayName = I18n.t(export_translation) + '[' + match[2] + ']';
    }
    else {
      var export_translation = 'plannings.export_file.' + columnKey;
      displayName = I18n.t(export_translation);
    }
    $(parentSel).append('<li data-value="' + columnKey + '">' + displayName + ' <a class="remove"><i class="fa fa-close fa-fw"></i></a></li>');
  };
  $.each(columnsExport, function(i, c) {
    if (columns.indexOf(c) >= 0)
      appendElement('#columns-export', c);
  });
  $.each(columnsSkip, function(i, c) {
    if (columns.indexOf(c) >= 0)
      appendElement('#columns-skip', c);
  });
  $('#columns-export a.remove').click(function(evt) {
    var $elem = $(evt.currentTarget).closest('li');
    if ($elem.parent()[0].id === 'columns-export') {
      var nextFocus = $elem.next();
      $('a.remove', $elem).hide();
      $('#columns-skip').append($elem);
      if (nextFocus.length) $('a.remove', nextFocus).show();
    }
  });
  $('#columns-export li').mouseenter(function(evt) {
    if ($(evt.currentTarget).closest('#columns-export').length > 0)
      $('a.remove', evt.currentTarget).show();
  }).mouseleave(function(evt) {
    $('a.remove', evt.currentTarget).hide();
  });
  if (localStorage.spreadsheetFormat)
    $('[name=spreadsheet-format][value=' + localStorage.spreadsheetFormat + ']').prop('checked', true);

  $('#btn-spreadsheet').click(function() {
    var planningsId = getPlanningsId();
    if (!planningId && planningsId.length == 0) {
      warning(I18n.t('plannings.index.export.none_planning'));
      return;
    }

    var spreadsheetStops = localStorage.spreadsheetStops = $('.spreadsheet-stops:checked').map(function(i, e) {
      return $(e).val();
    }).get().join('|');
    var spreadsheetColumnsExport = localStorage.spreadsheetColumnsExport = $('#columns-export li').map(function(i, e) {
      return $(e).attr('data-value');
    }).get().join('|');
    var spreadsheetColumnsSkip = localStorage.spreadsheetColumnsSkip = $('#columns-skip li').map(function(i, e) {
      return $(e).attr('data-value');
    }).get().join('|');
    var spreadsheetFormat = localStorage.spreadsheetFormat = $('[name=spreadsheet-format]:checked').val();
    var basePath = $('[name=spreadsheet-route]').val() ? ('/routes/' + $('[name=spreadsheet-route]').val()) : (planningId) ? '/plannings/' + planningId : '/plannings';

    window.location.href = basePath + '.' + spreadsheetFormat + '?stops=' + spreadsheetStops + '&columns=' + spreadsheetColumnsExport + "&ids=" + planningsId;

    $('#planning-spreadsheet-modal').modal('toggle');
  });
  $('.export_spreadsheet').click(function() {
    $('#planning-spreadsheet-modal').modal({
      keyboard: true,
      show: true
    });
  });
};

var plannings_form = function() {
  $('#planning_date').datepicker({
    language: I18n.currentLocale(),
    autoclose: true,
    calendarWeeks: true,
    todayHighlight: true,
    format: I18n.t("all.datepicker"),
    zIndexOffset: 1000
  });

  $('#planning_begin_date').datepicker({
    language: I18n.currentLocale(),
    autoclose: true,
    calendarWeeks: true,
    todayHighlight: true,
    format: I18n.t("all.datepicker"),
    zIndexOffset: 1000
  });

  $('#planning_end_date').datepicker({
    language: I18n.currentLocale(),
    autoclose: true,
    calendarWeeks: true,
    todayHighlight: true,
    format: I18n.t("all.datepicker"),
    zIndexOffset: 1000
  });

  var formatNoMatches = I18n.t('web.select2.empty_result');
  $('select#planning_tag_ids').select2({
    theme: 'bootstrap',
    minimumResultsForSearch: -1,
    templateSelection: templateTag,
    templateResult: templateTag,
    formatNoMatches: function() {
      return formatNoMatches;
    },
    width: '100%'
  });
};

var plannings_new = function(params) {
  'use strict';

  var onPlanningCreateModal = bootstrap_dialog({
    title: I18n.t('plannings.new.title'),
    icon: 'fa-calendar-check-o',
    message: SMT['modals/default_with_progress']({
      msg: I18n.t('plannings.new.dialog.new_planning')
    })
  });

  $('#new_planning').off('submit').on('submit', function(event) {
    onPlanningCreateModal.modal("show");
  });

  plannings_form();
  $("#planning_zoning_ids").select2({
    theme: 'bootstrap'
  });
};

var plannings_edit = function(params) {
  'use strict';

  plannings_form();

  var prefered_unit = (!params.prefered_unit ? "km" : params.prefered_unit),
    planning_id = params.planning_id,
    planning_ref = params.planning_ref,
    user_api_key = params.user_api_key,
    zoning_ids = params.zoning_ids,
    vehicles_array = params.vehicles_array,
    vehicles_usages_map = params.vehicles_usages_map,
    withStopsInSidePanel = params.with_stops,
    url_click2call = params.url_click2call,
    layer_zoning,
    lastPopover,
    nbBackgroundTaskErrors = 0,
    backgroundTaskIntervalId,
    currentZoom = 17,
    needUpdateStopStatus = params.update_stop_status && withStopsInSidePanel,
    enableStopStatus = params.enable_stop_status,
    outOfRouteId = params.routes_array.filter(function(route) {
      return !route.vehicle_usage_id;
    }).map(function(route) {
      return route.route_id;
    })[0],
    routes = $.map(params.routes_array, function(route) {
      if (route.vehicle_usage_id) {
        var vehicle_usage = {};
        $.each(vehicles_usages_map, function(i, v) {
          if (v.vehicle_usage_id == route.vehicle_usage_id) {
            vehicle_usage = v;
          }
        });
        route.name = (route.ref ? (route.ref + ' ') : '') + vehicle_usage.name;
        if (!route.color) {
          route.color = vehicle_usage.color;
        }
      }
      return route;
    }),
    vehicleIdsPosition = vehicles_array.filter(function(vehicle) {
      return vehicle.available_position;
    }).map(function(vehicle) {
      return vehicle.id;
    });

  function getZonings() {
    return $("#planning_zoning_ids").val() || [];
  }

  var apply_zoning_modal = bootstrap_dialog({
    title: I18n.t('plannings.edit.dialog.zoning.title'),
    icon: 'fa-bars',
    message: SMT['modals/default_with_progress']({
      msg: I18n.t('plannings.edit.dialog.zoning.in_progress')
    })
  });

  $('.update-zonings-form').submit(function(e) {
    e.preventDefault();
    if (!confirm(I18n.t('plannings.edit.zoning_confirm'))) return;
    $.ajax({
      url: $(e.target).attr('action'),
      type: 'PATCH',
      data: {
        planning: { zoning_ids: getZonings() },
        with_stops: withStopsInSidePanel
      },
      dataType: 'json',
      beforeSend: function() {
        apply_zoning_modal.modal('show');
      },
      complete: function() {
        apply_zoning_modal.modal('hide');
      },
      success: function(data) {
        updatePlanning(data, {
          'partial': false
        });
        $('.update-zonings-form button[type=submit]').removeClass('btn-warning').addClass('btn-default').removeAttr('title');
        notice(I18n.t('plannings.edit.zonings.success'));
        zoning_ids = getZonings();
      },
      error: function() {
        stickyError(I18n.t('plannings.edit.zonings.fail'));
      }
    });
  });

  // Ensure touch compliance with chrome like browser
  L.controlTouchScreenCompliance();
  // sidebar has to be created before map
  var sidebar = L.control.sidebar('edit-planning', {
    position: 'right'
  });

  sidebar.open('planning-pane');

  var vehicleLayer;
  var vehicleMarkers = [];

  var displayVehicles = function(data) {
    data.forEach(function(pos) {
      if ($.isNumeric(pos.lat) && $.isNumeric(pos.lng)) {
        var route = routes.filter(function(route) {
          return route.vehicle_usage_id == vehicles_usages_map[pos.vehicle_id].vehicle_usage_id;
        })[0];
        var isMoving = pos.speed && (Date.parse(pos.time) > Date.now() - 600 * 1000);
        var direction_icon = pos.direction ? '<i class="fa fa-location-arrow fa-stack-1x vehicle-direction" style="transform: rotate(' + (parseInt(pos.direction) - 45) + 'deg);" />' : '';
        var iconContent = isMoving ?
          '<span class="fa-stack" data-route_id="' + route.route_id + '"><i class="fa fa-truck fa-stack-2x vehicle-icon pulse" style="color: ' + (route.color || vehicles_usages_map[pos.vehicle_id].color) + '"></i>' + direction_icon + '</span>' :
          '<i class="fa fa-truck fa-lg vehicle-icon" style="color: ' + (route.color || vehicles_usages_map[pos.vehicle_id].color) + '"></i>';
        vehicleLayer.removeLayer(vehicleMarkers[pos.vehicle_id]);
        vehicleMarkers[pos.vehicle_id] = L.marker(new L.LatLng(pos.lat, pos.lng), {
          icon: new L.divIcon({
            html: iconContent,
            iconSize: new L.Point(24, 24),
            iconAnchor: new L.Point(12, 12),
            popupAnchor: new L.Point(0, -12),
            className: 'vehicle-position'
          }),
          zIndexOffset: 800,
          title: vehicles_usages_map[pos.vehicle_id].name + ' - ' + pos.device_name + ' - ' + I18n.t('plannings.edit.vehicle_speed') + ' ' + (prefered_unit == 'km' ? (pos.speed || 0) + ' km/h - ' : (Math.ceil10(pos.speed/1.609344) || 0) + ' mph - ') + I18n.t('plannings.edit.vehicle_last_position_time') + ' ' + (pos.time_formatted || (new Date(pos.time)).toLocaleString()),
        }).addTo(vehicleLayer);
      }
    });
  };

  var requestVehiclePositionPending = false;
  var requestVehiclePosition = function() {
    if (!requestVehiclePositionPending) {
      $.ajax({
        type: 'GET',
        url: '/api/0.1/vehicles/current_position.json',
        data: {
          ids: vehicleIdsPosition
        },
        dataType: 'json',
        beforeSend: function() {
          requestVehiclePositionPending = true;
        },
        complete: function() {
          requestVehiclePositionPending = false;
        },
        success: function(data) {
          if (data && data.errors) {
            nbBackgroundTaskErrors++;
            if (nbBackgroundTaskErrors > 1) clearInterval(backgroundTaskIntervalId);
            $.each(data.errors, function(i, error) {
              stickyError(I18n.t('plannings.edit.current_position') + ' ' + error);
            });
          } else {
            displayVehicles(data);
          }
        },
        error: function() {
          nbBackgroundTaskErrors++;
          if (nbBackgroundTaskErrors > 1) clearInterval(backgroundTaskIntervalId);
        }
      });
    }
  };

  var updateStopsStatus = function(data) {

    var updateStopStatusContent = function(content, stop) {
      var $elt = content.find('.toggle-status, .number .stop-status');
      var hadStatus = ($elt.css('display') == 'none') ? false : true;
      if (stop.status) {
        if ($elt.css('display') == 'none') $elt.show();
      }
      else {
        if ($elt.css('display') != 'none') $elt.hide();
      }
      $elt = content.find('.stop-status');
      $.each($elt, function(i, elt) {
        $elt = $(elt);
        if (!stop.status || stop.status && !$elt.hasClass('stop-status-' + stop.status_code)) {
          $elt.removeClass().addClass('stop-status' + (stop.status_code ? ' stop-status-' + stop.status_code : ''));
          $elt.attr({
            title: stop.status + (stop.eta_formated ? ' - ' + I18n.t('plannings.edit.popup.eta') + ' ' + stop.eta_formated : '')
          });
        }
      });
      var name = content.find('.title .name');
      name.attr('title') && (!stop.status || name.attr('title').search(stop.status) == -1) && name.attr({
        title: name.attr('title').substr(0, hadStatus ? name.attr('title').lastIndexOf(' - ') : name.attr('title').length) + (stop.status ? ' - ' + stop.status : '')
      });
      name = content.find('.status');
      if (name.text() != stop.status) name.text(stop.status);
      name = content.find('.eta');
      if (name.text() != stop.eta_formated) name.text(stop.eta_formated);
      return content;
    };

    var updateRouteQuantities = function(content, route) {
      route.quantities.forEach(function (quantity) {
        var $quantity = content.find("[data-quantity_id='" + quantity.deliverable_unit_id + "']");
        if ($quantity.length > 0) {
          var label = $quantity.text().split(/\s{1}/)[1];
          if (label) {
            $quantity.text(quantity.quantity + ' ' + label);
          }
        }
      })
    };

    if (data) {
      var routeL, routeStops, marker, $item;

      data.forEach(function(route) {
        if (route.vehicle_usage_id) {
          var $route = $("[data-route_id='" + route.id + "']");
          updateRouteQuantities($route, route);

          route.stops.forEach(function(stop) {
            var sort = function(element) {
              return (element.properties.index == stop.index) ? element : void(0);
            };

            routeL = routesLayer.clustersByRoute[route.id];
            if (routeL) {
              routeStops = routeL.getLayers();
              marker = routeStops.filter(sort)[0];

              if (marker) {
                marker.properties.tomtom = stop;
              }
            }
            $.each($("[data-stop_id='" + stop.id + "']"), function(i, item) {
              // update list, active popup in map and active popover
              $item = $(item);
              updateStopStatusContent($item, stop);
            });
          });
        }
      });
    }
  };

  var requestUpdateStopsStatusPending = false;
  var requestUpdateStopsStatus = function() {
    if (!requestUpdateStopsStatusPending) {
      $.ajax({
        type: 'PATCH',
        url: '/api/0.1/plannings/' + planning_id + '/update_stops_status.json',
        dataType: 'json',
        data: {
          details: true
        },
        beforeSend: function() {
          requestUpdateStopsStatusPending = true;
        },
        complete: function() {
          requestUpdateStopsStatusPending = false;
        },
        success: function(data) {
          if (data && data.errors) {
            nbBackgroundTaskErrors++;
            if (nbBackgroundTaskErrors > 1) clearInterval(backgroundTaskIntervalId);
            $.each(data.errors, function(i, error) {
              stickyError(I18n.t('plannings.edit.update_stops_status') + ' ' + error);
            });
          } else {
            updateStopsStatus(data);
          }
        },
        error: function() {
          nbBackgroundTaskErrors++;
          if (nbBackgroundTaskErrors > 1) clearInterval(backgroundTaskIntervalId);
        }
      });
    }
  };

  var backgroundTask = function() {
    if (vehicleIdsPosition.length) {
      requestVehiclePosition();
    }
    if (needUpdateStopStatus) {
      requestUpdateStopsStatus();
    }
  };

  if (vehicleIdsPosition.length || needUpdateStopStatus) {
    if (vehicleIdsPosition.length) {
      vehicleLayer = L.featureGroup();
      if (!params.overlay_layers) params.overlay_layers = {};
      params.overlay_layers[I18n.t("plannings.edit.vehicles")] = vehicleLayer;
    }
    backgroundTask();
    backgroundTaskIntervalId = setInterval(backgroundTask, 60000);
    $(document).on('page:before-change', function() {
      clearInterval(backgroundTaskIntervalId);
    });
  }

  params.geocoder = true;

  var map = mapInitialize(params);
  var popupOptions = {};
  $.each(params.manage_planning, function(i, elt) {
    popupOptions['manage_' + elt] = true;
  });
  var routesLayer = new RoutesLayer(planning_id, {
    url_click2call: url_click2call,
    unit: prefered_unit,
    outOfRouteId: outOfRouteId,
    routes: routes,
    colorsByRoute: params.colors_by_route,
    appBaseUrl: params.apiWeb ? '/api-web/0.1/' : '/',
    popupOptions: popupOptions,
    disableClusters: params.disable_clusters,
    withStops: params.with_stops
  }).on('clickStop', function(stop) {
    enlightenStop({index: stop.index, routeId: stop.routeId});
  }).addTo(map);

  if (vehicleLayer) map.addLayer(vehicleLayer);

  L.control.attribution({
    prefix: false,
    position: 'bottomleft'
  }).addTo(map);
  L.control.scale({
    imperial: false
  }).addTo(map);

  L.disableClustersControl(map, routesLayer);

  var fitBounds = initializeMapHash(map);

  sidebar.addTo(map);

  $('#lock_routes_dropdown li a, #toggle_routes_dropdown li a').click(function() {
    if (routes.length == 0) return;

    var action = $(this).parent('li').parent('ul').attr('id') == 'lock_routes_dropdown' ? 'lock' : 'toggle';
    var selection = $(this).parent('li').data('selection');

    var successLock = function(data) {
      $.each(data, function(index, route) {
        var element = $("[data-route_id='" + route.id + "']");
        if (route.locked) {
          element.find(".lock").removeClass("btn-default").addClass("btn-warning");
          element.find('.lock i').removeClass('fa-unlock').addClass('fa-lock');
        } else {
          element.find(".lock").removeClass("btn-warning").addClass("btn-default");
          element.find('.lock i').removeClass('fa-lock').addClass('fa-unlock');
        }
      });
      checkLockAndActive();
    };
    var successToggle = function(data) {
      if (selection == 'all' || selection == 'reverse') {
        routesLayer.showAllRoutes();
      } else if (selection == 'none') {
        routesLayer.hideAllRoutes();
      }
      $.each(data, function(index, route) {
        var element = $("[data-route_id='" + route.id + "']");
        if (route.hidden) {
          element.find("ul.stops").hide();
          element.find('.toggle i').removeClass('fa-eye').addClass('fa-eye-slash');
        } else {
          element.find("ul.stops").show();
          element.find('.toggle i').removeClass('fa-eye-slash').addClass('fa-eye');
        }
      });
    };

    $.ajax({
      url: '/api/0.1/plannings/' + planning_id + '/update_routes',
      type: 'PATCH',
      data: {
        route_ids: $.map(routes, function(route) {
          return route.route_id;
        }),
        selection: selection,
        action: action
      },
      dataType: 'json',
      beforeSend: beforeSendWaiting,
      complete: completeAjaxMap,
      error: ajaxError,
      success: action == 'lock' ? successLock : successToggle
    });

  });

  // Used to highlight the current stop (or route if over 1t points) in sidebar routes
  var enlightenStop = function(stop) {
    var target;

    if (stop.index) {
      target = $(".routes [data-route_id='" + stop.routeId + "'] [data-stop_index='" + stop.index + "']");
    } else {
      target = $("[data-stop_id='" + stop.id + "']");
    }

    if (target.length === 0) {
      target = $(".routes [data-route_id='" + stop.routeId + "']");
    } else {
      target.css("background", "orange");
      setTimeout(function() {
        target.css("background", "");
      }, 1500);
    }

    if (target.offset() && (target.offset().top < 0 || target.offset().top > $(".sidebar-content").height())) {
      $(".sidebar-content").animate({
        scrollTop: target.offset().top + $(".sidebar-content").scrollTop() - 100
      });
    }
  };

  layer_zoning = (new L.FeatureGroup()).addTo(map);
  var zoneGeometry = L.GeoJSON.extend({
    addOverlay: function(zone) {
      var that = this;
      var labelLayer = (new L.layerGroup()).addTo(map);
      var labelMarker;
      this.on('mouseover', function() {
        that.setStyle({
          opacity: 0.9,
          weight: (zone.speed_multiplicator === 0) ? 5 : 3
        });
        if (zone.name) labelMarker = L.marker(that.getBounds().getCenter(), {
          icon: L.divIcon({
            className: 'label',
            html: zone.name,
            iconSize: [100, 40]
          })
        }).addTo(labelLayer);
      });
      this.on('mouseout', function() {
        that.setStyle({
          opacity: 0.5,
          weight: (zone.speed_multiplicator === 0) ? 5 : 2
        });
        if (labelMarker) labelLayer.removeLayer(labelMarker);
        labelMarker = null;
      });
      return this;
    }
  });

  var displayZoning = function(zoning) {
    $.each(zoning.zones, function(index, zone) {
      var geoJsonLayer = (new zoneGeometry(JSON.parse(zone.polygon))).addOverlay(zone);
      var geom = geoJsonLayer.getLayers()[0];
      if (geom) {
        geom.setStyle((zone.speed_multiplicator === 0) ? {
          color: '#FF0000',
          fillColor: '#707070',
          opacity: 0.5,
          weight: 5,
          dashArray: '10, 10',
          fillPattern: stripes
        } : {
          color: (zone.vehicle_id && vehicles_usages_map[zone.vehicle_id] ? vehicles_usages_map[zone.vehicle_id].color : '#707070'),
          fillColor: null,
          opacity: 0.5,
          weight: 2,
          dashArray: 'none',
          fillPattern: null
        });
        geom.addTo(layer_zoning);
      }
    });

    if (fitBounds) {
      var bounds = layer_zoning.getBounds();
      if (bounds && bounds.isValid()) {
        map.invalidateSize();
        map.fitBounds(bounds, {
          maxZoom: 15,
          animate: false,
          padding: [20, 20]
        });
      }
    }
  };

  var stripes = new L.StripePattern({
    color: '#FF0000',
    angle: -45
  });
  stripes.addTo(map);

  var templateSelectionZoning = function(state) {
    if (state.id)
      return $('<span><span class="zoning_name">' + state.text + '</span> <a href="/zonings/' + state.id + '/edit/planning/' + planning_id + '?back=true" title="' + I18n.t('plannings.edit.zoning_edit') + '"><i class="fa fa-pencil fa-fw"></i></a></span>');
  };

  $('#planning_zoning_ids').select2({
    theme: 'bootstrap',
    templateSelection: templateSelectionZoning
  });

  $('#planning_zoning_ids').change(function() {
    layer_zoning.clearLayers();
    var ids = $(this).val();
    if (ids && ids.length > 0) {
      $.each(ids, function(i, id) {
        $.ajax({
          type: 'GET',
          url: '/api/0.1/zonings/' + id + '.json',
          beforeSend: beforeSendWaiting,
          success: displayZoning,
          complete: completeAjaxMap,
          error: ajaxError
        });
      });
    }
  });

  var dialog_optimizer;
  var initOptimizerDialog = function() {
    hideNotices(); // Clear Failed Optimization Notices
    dialog_optimizer = bootstrap_dialog({
      title: I18n.t('plannings.edit.dialog.optimizer.title'),
      icon: 'fa-gear',
      message: SMT['modals/optimize']({
        i18n: mustache_i18n
      })
    });
  };
  initOptimizerDialog();

  $('#optimize_each_all, #optimize_global_all, #optimize_each_actives, #optimize_global_actives').click(function() {
    if (!confirm(I18n.t($(this).data('opti-global') ? 'plannings.edit.optimize_global.confirm' : 'plannings.edit.optimize_each.confirm'))) {
      return false;
    }
    $.ajax({
      type: 'GET',
      url: '/plannings/' + planning_id + '/optimize.json',
      data: {
        with_stops: withStopsInSidePanel,
        global: $(this).data('opti-global'),
        active_only: $(this).data('active-only')
      },
      beforeSend: beforeSendWaiting,
      success: function(data) {
        displayPlanning(data, {
          error: function() {
            stickyError(I18n.t('plannings.edit.optimize_failed'));
          },
          success: function() {
            notice(I18n.t('plannings.edit.optimize_complete'));
          }
        });
      },
      complete: completeAjaxMap,
      error: ajaxError
    });
  });

  var sortPlanning = function(event, ui) {
    var item = $(ui.item),
      index = 0,
      route = item.closest('[data-route_id]'),
      stops = $('.sortable li[data-stop_id]', route),
      route_id = route.attr('data-route_id'),
      stop_id = item.closest("[data-stop_id]").attr("data-stop_id");
    while (stops[index].attributes['data-stop_id'].value != stop_id) {
      index++;
    }
    $.ajax({
      type: 'PATCH',
      url: '/plannings/' + planning_id + '/' + route_id + '/' + stop_id + '/move/' + (index + 1) + '.json',
      beforeSend: beforeSendWaiting,
      success: updatePlanning,
      complete: completeAjaxMap,
      error: function(request, status, error) {
        ajaxError(request, status, error);
        $(".route[data-route_id] .stops.sortable").sortable('cancel');
      }
    });
  };

  var externalCallbackUrl = function(context) {
    $('.customer_external_callback_url', context).off('click').click(function(e) {
      $.ajax({
        url: $(e.target).data('url'),
        type: 'GET',
        beforeSend: beforeSendWaiting,
        complete: completeWaiting,
        success: function() {
          notice(I18n.t('plannings.edit.export.customer_external_callback_url.success'));
        },
        error: function() {
          stickyError(I18n.t('plannings.edit.export.customer_external_callback_url.fail'));
        }
      });
    });
  };

  var templateSelectionColor = function(state) {
    if (state.id) {
      return $("<span class='color_small' style='background:" + state.id + "'></span>");
    } else {
      return $("<i />").addClass("fa fa-paint-brush").css("color", "#CCC");
    }
  };

  var templateResultColor = function(state) {
    if (state.id) {
      return $("<span class='color_small' style='background:" + state.id + "'></span>");
    } else {
      return $("<span class='color_small' data-color=''></span>");
    }
  };

  var templateSelectionVehicles = function(state) {
    if (state.id) {
      var color = $('.color_select', $(state.element).parent().parent()).val();
      if (color) {
        return $("<span/>").text(vehicles_usages_map[state.id].name);
      } else {
        return $("<span><span class='color_small' style='background:" + vehicles_usages_map[state.id].color + "'></span>&nbsp;</span>").append($("<span/>").text(vehicles_usages_map[state.id].name));
      }
    }
  };

  var templateResultVehicles = function(state) {
    if (state.id) {
      return $("<span><span class='color_small' style='background:" + vehicles_usages_map[state.id].color + "'></span>&nbsp;</span>").append($("<span/>").text(vehicles_usages_map[state.id].name));
    }
  };

  var switchVehicleModal = bootstrap_dialog({
    title: I18n.t('plannings.edit.dialog.vehicle.title'),
    icon: 'fa-bars',
    message: SMT['modals/default_with_progress']({
      msg: I18n.t('plannings.edit.dialog.vehicle.in_progress')
    })
  });

  // called first during plan initialization (context: plan), and several times after a route need to be refreshed (context: route)
  var initRoutes = function(context, data, options) {

    fake_select2($(".color_select", context), function(select) {
      select.select2({
        minimumResultsForSearch: -1,
        templateSelection: templateSelectionColor,
        templateResult: templateResultColor,
        formatNoMatches: I18n.t('web.select2.empty_result')
      }).select2("open");
      select.next('.select2-container--bootstrap').addClass('input-sm');
    });

    fake_select2($(".vehicle_select", context), function(select) {
      select.select2({
        minimumResultsForSearch: -1,
        data: vehicles_array,
        templateSelection: templateSelectionVehicles,
        templateResult: templateResultVehicles,
        formatNoMatches: I18n.t('web.select2.empty_result')
      }).select2("open");
      select.next('.select2-container--bootstrap').addClass('input-sm');
    });

    var $routes = context.hasClass('route') ? context : $(".route", context);

    // Following callbacks need to be set as many as route has changed
    $routes.off('change').on('change', "[name=route\\\[color\\\]]", function() {
      var id = $(this).closest('[data-route_id]').attr('data-route_id');
      var color = this.value;
      if (color)
        $('.color_small', $('.vehicle_select', $(this).parent()).next()).hide();
      else
        $('.color_small', $('.vehicle_select', $(this).parent()).next()).show();
      $.ajax({
        type: 'PUT',
        data: JSON.stringify({
          color: color
        }),
        contentType: 'application/json',
        url: '/api/0.1/plannings/' + planning_id + '/routes/' + id + '.json',
        success: function() {
          routesLayer.options.colorsByRoute[id] = color;
          routesLayer.refreshRoutes([id]);
        },
        error: ajaxError
      });
      routes.forEach(function(route) {
        if (route.route_id == id) {
          route.color = color;
          if (!color) {
            for (var vehicle_id in vehicles_usages_map) {
              if (vehicles_usages_map[vehicle_id].vehicle_usage_id == route.vehicle_usage_id)
                color = vehicles_usages_map[vehicle_id].color;
            }
          }
        }
      });
      $('li[data-route_id=' + id + '] li[data-store_id] > i.fa').css('color', color);
      $('li[data-route_id=' + id + '] li[data-stop_id] .number:not(.color_force)').css('background', color);
      $('span[data-route_id=' + id + '] i.vehicle-icon').css('color', color);
    });

    $('.vehicle_select', context).off('change').change(function() {
      var $this = $(this);
      var initial_value = $this.data("initial-value");
      if (initial_value !== $this.val()) {
        $.ajax({
          type: 'PATCH',
          data: JSON.stringify({
            route_id: $this.closest('[data-route_id]').attr('data-route_id'),
            vehicle_usage_id: vehicles_usages_map[$this.val()].vehicle_usage_id
          }),
          contentType: 'application/json',
          url: '/plannings/' + planning_id + '/switch.json',
          beforeSend: function() {
            beforeSendWaiting();
            switchVehicleModal.modal('show');
          },
          success: function(data) {
            displayPlanning(data, {
              partial: 'routes'
            });
          },
          complete: function() {
            completeAjaxMap();
            switchVehicleModal.modal('hide');
          },
          error: ajaxError
        });
      }
    });

    // Following callbacks need to be set only once
    if (!options || !options.skipCallbacks) {
      externalCallbackUrl(context);

      devicesObservePlanning.init(context, function(from) {
        if (from && from.data('service') == 'tomtom' && enableStopStatus) {
          needUpdateStopStatus = true;
          requestUpdateStopsStatus();
        }
      });

      $('.export_spreadsheet', context).click(function() {
        $('[name=spreadsheet-route]').val($(this).closest('[data-route_id]').attr('data-route_id'));
        $('#planning-spreadsheet-modal').modal({
          keyboard: true,
          show: true
        });
      });

      $('.kmz_email a', context).click(function(e) {
        e.preventDefault();
        $.ajax({
          url: $(e.target).attr('href'),
          type: 'GET',
          beforeSend: beforeSendWaiting,
          complete: completeWaiting,
          success: function() {
            notice(I18n.t('plannings.edit.export.kmz_email.success'));
          },
          error: function() {
            stickyError(I18n.t('plannings.edit.export.kmz_email.fail'));
          }
        });
      });

      iCalendarExport(planning_id);

      $('.routes', context).sortable({
        disabled: true,
        items: 'li.route'
      });

      $routes
        .on("click", ".toggle", function() {
          var id = $(this).closest("[data-route_id]").attr("data-route_id");
          var li = $("ul.stops, ol.stops", $(this).closest("li"));
          li.toggle();
          var hidden = !li.is(":visible");
          var i = $("i", this);
          $.ajax({
            type: 'PUT',
            data: JSON.stringify({
              hidden: hidden,
              geojson: (id in routesLayer.clustersByRoute) ? 'false' : 'polyline'
            }),
            contentType: 'application/json',
            url: '/api/0.1/plannings/' + planning_id + '/routes/' + id + '.json',
            success: function(data) {
              if (hidden) {
                i.removeClass("fa-eye").addClass("fa-eye-slash");
                routesLayer.hideRoutes([id]);
              } else {
                i.removeClass("fa-eye-slash").addClass("fa-eye");
                routesLayer.showRoutes([id], JSON.parse(data.geojson));
              }
            },
            error: ajaxError
          });
        })
        .on("click", ".marker", function() {
          var stopIndex = $(this).closest("[data-stop_index]").attr("data-stop_index");
          if (stopIndex) {
            var routeId = $(this).closest("[data-route_id]").attr("data-route_id");
            routesLayer.focus({routeId: routeId, stopIndex: stopIndex});
          } else {
            var storeId = $(this).closest("[data-store_id]").attr("data-store_id");
            if (storeId) {
              routesLayer.focus({storeId: storeId});
            }
          }
          $(this).blur();
          return false;
        })
        .on('click', '.optimize', function() {
          initOptimizerDialog();
          if (!confirm(I18n.t('plannings.edit.optimize_confirm')))
            return;

          var id = $(this).closest('[data-route_id]').attr('data-route_id');
          // Call optimize_route
          $.ajax({
            type: 'GET',
            url: '/plannings/' + planning_id + '/' + id + '/optimize.json',
            data: {
              with_stops: true,
              active_only: $(this).data('active-only')
            },
            beforeSend: beforeSendWaiting,
            success: function(data) {
              updatePlanning(data, {
                error: function() {
                  stickyError(I18n.t('plannings.edit.optimize_failed'));
                },
                success: function() {
                  notice(I18n.t('plannings.edit.optimize_complete'));
                }
              });
            },
            complete: completeAjaxMap,
            error: ajaxError
          });
        })
        .on("click", ".active_all, .active_reverse, .active_none, .active_status, .reverse_order", function() {
          var url = this.href;
          $.ajax({
            type: 'PATCH',
            url: url,
            beforeSend: beforeSendWaiting,
            success: updatePlanning,
            complete: completeAjaxMap,
            error: ajaxError
          });
          if ($(this).hasClass('reverse_order'))
            $(this).closest(".dropdown-menu").prev().dropdown("toggle");
          return false;
        })
        .on("change", "[name=route\\\[ref\\\]]", function() {
          var id = $(this).closest("[data-route_id]").attr("data-route_id");
          var ref = this.value;
          $.ajax({
            type: 'PUT',
            data: JSON.stringify({
              ref: ref
            }),
            contentType: 'application/json',
            url: '/api/0.1/plannings/' + planning_id + '/routes/' + id + '.json',
            error: ajaxError
          });
        });

      $(".lock", context).click(function() {
        var id = $(this).closest("[data-route_id]").attr("data-route_id");
        var i = $("i", this);
        i.toggleClass("fa-lock");
        i.toggleClass("fa-unlock");
        $(this).toggleClass("btn-default");
        $(this).toggleClass("btn-warning");
        var locked = i.hasClass("fa-lock");
        checkLockAndActive();
        $.ajax({
          type: 'PUT',
          data: JSON.stringify({
            locked: locked
          }),
          contentType: 'application/json',
          url: '/api/0.1/plannings/' + planning_id + '/routes/' + id + '.json',
          error: ajaxError
        });
      });

      $('.load-stops', context).click(function(event) {
        var routeId = $(event.target).closest('[data-route_id]').attr('data-route_id');
        $.ajax({
          type: 'GET',
          contentType: 'application/json',
          url: '/plannings/' + planning_id + '.json',
          data: {
            route_ids: routeId
          },
          beforeSend: beforeSendWaiting,
          success: function(data) {
            updatePlanning(data, {
              skipMap: true
            });
          },
          complete: completeAjaxMap,
          error: ajaxError
        });
      });
    }
  };

  var checkLockAndActive = function() {
    var maxUnlockedStops = 0;
    $('[data-route_id]').each(function() {
      var isRouteLocked = $(this).find('.lock i').hasClass('fa-lock');
      var stopCount = $(this).find('[data-size-active]').data('size-active');

      if (!isRouteLocked && stopCount)
        maxUnlockedStops = Math.max(maxUnlockedStops, stopCount);
      if (!isRouteLocked && stopCount > 1) {
        $(this).find('.optimize').parent().parent().prevAll('.btn').prop('disabled', false);
      }
      else
        $(this).find('.optimize').parent().parent().prevAll('.btn').prop('disabled', true);
    });

    if (!maxUnlockedStops) {
      $('#planning_zoning_button').attr('disabled', 'disabled');
    } else {
      $('#planning_zoning_button').removeAttr('disabled');
    }
    if (maxUnlockedStops < 2) {
      $('#global_tools').find('button').first().attr('disabled', 'disabled');
    } else {
      $('#global_tools').find('button').first().removeAttr('disabled');
    }
  };

  var buildUrl = function(url, hash) {
    $.each(hash, function(k, v) { url = url.replace('\{' + k.toUpperCase() + '\}', hash[k]) });
    return url;
  };

  // Depending 'options.partial' this function is called for initialization or for pieces of planning
  var displayPlanning = function(data, options) {
    if (!progressDialog(data.optimizer, dialog_optimizer, '/plannings/' + planning_id + '.json' + (options.firstTime ? '?with_stops=' + withStopsInSidePanel : ''), displayPlanning, options)) {
      return;
    }

    function api_route_calendar_path(route) {
      return '/api/0.1/plannings/' + (planning_ref ? 'ref:' + encodeURIComponent(planning_ref) : planning_id) +
        '/routes/' + (route.ref ? 'ref:' + encodeURIComponent(route.ref) : route.route_id) + '.ics';
    }

    function setRouteVariables(i, route) {
      route.calendar_url = api_route_calendar_path(route);
      route.calendar_url_api_key = api_route_calendar_path(route) + '?api_key=' + user_api_key;

      if (route.vehicle_id) {
        route.vehicle = vehicles_usages_map[route.vehicle_id];
        route.path = '/vehicle_usages/' + route.vehicle_usage_id + '/edit?back=true';
      }

      route.customer_enable_external_callback = data.customer_enable_external_callback;
      if (data.customer_external_callback_url) {
        route.customer_external_callback_url = buildUrl(data.customer_external_callback_url, { planning_id: data.id, route_id: route.route_id, planning_ref: data.ref, route_ref: route.ref });

        if (data.customer_enable_external_callback)
          $("#global_tools .customer_external_callback_url, #external-callback-btn").data('url', buildUrl(data.customer_external_callback_url, { planning_id: data.id, planning_ref: data.ref }));
      }
    }

    data.i18n = mustache_i18n;
    data.planning_id = data.id;

    var empty_colors = params.vehicle_colors.slice();
    empty_colors.unshift('');

    var updateColorsForRoutesAndStops = function(i, route) {
      route.colors = $.map(empty_colors, function(color) {
        return {
          color: color,
          selected: route.color === color
        };
      });
      $.each(route.stops, function(i, stop) {
        if (stop.destination && stop.destination.color) {
          stop.destination.color_force = true;
        } else {
          stop.color = route.color;
        }
      });
    };

    $.each(data.routes, function(i, route) {
      setRouteVariables(i, route);

      // update global routes
      if (typeof options !== 'object' || options.partial != 'stops') {
        var vehicle_usage = {};
        $.each(vehicles_usages_map, function(i, v) {
          if (v.vehicle_usage_id == route.vehicle_usage_id) vehicle_usage = v;
        });
        $.each(routes, function(i, rv) {
          if (rv.route_id == route.route_id)
            routes[i] = {
              route_id: route.route_id,
              color: route.color || vehicle_usage.color,
              vehicle_usage_id: route.vehicle_usage_id,
              ref: route.ref,
              name: (route.ref ? (route.ref + ' ') : '') + vehicle_usage.name,
              outdated: route.outdated
            };
        });
        updateColorsForRoutesAndStops(i, route);
      }
    });

    // 1st case: the whole planning needs to be initialized and displayed
    if (typeof options !== 'object' || !options.partial) {
      data.ref = null; // here to prevent mustache template to get the value
      $.each(params.manage_planning, function(i, elt) {
        data['manage_' + elt] = true;
      });
      data.callback_button = params.callback_button;
      $("#planning").html(SMT['plannings/edit'](data));

      initRoutes($('#edit-planning'), data, options);

      if (options.firstTime) {
        routesLayer.showAllRoutes({stores: true}, function() {
          if (fitBounds) {
            var bounds = routesLayer.getBounds();
            if (bounds && bounds.isValid()) {
              map.invalidateSize();
              map.fitBounds(bounds, {
                maxZoom: 15,
                animate: false,
                padding: [20, 20]
              });
            }
          }
        });
      }
      else {
        routesLayer.showAllRoutes();
      }

      $('#refresh').click(function() {
        $.ajax({
          type: 'GET',
          url: '/plannings/' + planning_id + '/refresh.json?with_stops=' + withStopsInSidePanel,
          beforeSend: beforeSendWaiting,
          success: displayPlanning,
          complete: completeAjaxMap,
          error: ajaxError
        });
      });
    }
    // 2nd case: several routes needs to be displayed (header and map), for instance by switching vehicles
    else if (typeof options === 'object' && options.partial === 'routes') {
      $.each(data.routes, function(i, route) {
        var vehicle_usage = {};
        $.each(vehicles_usages_map, function(i, v) {
          if (v.vehicle_usage_id == route.vehicle_usage_id) vehicle_usage = v;
        });
        routesLayer.options.colorsByRoute[route.route_id] = route.color || vehicle_usage.color;
      });

      var routeIds = [];
      $.each(data.routes, function(i, route) {
        routeIds.push(route.route_id);
        route.i18n = mustache_i18n;
        route.planning_id = data.id;
        route.routes = routes;
        $.each(params.manage_planning, function(i, elt) {
          route['manage_' + elt] = true;
        });

        $(".route[data-route_id='" + route.route_id + "']").html(SMT['routes/edit'](route));

        initRoutes($(".route[data-route_id='" + route.route_id + "']"), data, $.merge({skipCallbacks: true}, options));

        var regExp = new RegExp('/plannings/' + route.planning_id + '/' + route.route_id + '/[0-9]+/move.json');
        // popups are not selected follow
        $.each($('.send_to_route'), function(j, link) {
          var $link = $(link);
          if ($link.attr('href').match(regExp) != null)
            $link.html('<div class="color_small" style="background:' + (route.color || route.vehicle.color) + '"></div> ' + route.vehicle.name);
        });
        $.each($('li[data-stop_id]'), function(i, stop) {
          var popupContent = $(stop).data()['bs.popover'] && $($(stop).data()['bs.popover'].options.content);
          if (popupContent) {
            $.each($('.send_to_route', popupContent), function(j, link) {
              var $link = $(link);
              if ($link.attr('href').match(regExp) != null)
                $link.html('<div class="color_small" style="background:' + (route.color || route.vehicle.color) + '"></div> ' + route.vehicle.name);
            });
            $(stop).data()['bs.popover'].options.content = popupContent;
          }
        });
      });

      routesLayer.refreshRoutes(routeIds);
    }
    // 3rd case: only stops needs to be refreshed, for instance after moving stop
    else if (typeof options === 'object' && options.partial === 'stops') {
      $.each(data.routes, function(i, route) {
        route.i18n = mustache_i18n;
        route.planning_id = data.id;
        route.routes = routes;
        $.each(params.manage_planning, function(i, elt) {
          route['manage_' + elt] = true;
        });

        $(".route[data-route_id='" + route.route_id + "'] .route-details").html(SMT['stops/list'](route));

        if (!options || !options.skipMap) {
          routesLayer.refreshRoutes([route.route_id]);
        }
      });

      $('.global_info').html(SMT['plannings/edit_head'](data));
    }

    $("#out_of_route .sortable").sortable({
      connectWith: ".sortable",
      update: sortPlanning
    }).disableSelection();

    var routesWithVehicle = routes.filter(function(route) { return route.vehicle_usage_id; } );
    $.each(data.routes, function(i, route) {
      var sortableUpdate = false;
      $(".route[data-route_id='" + route.route_id + "'] .stops.sortable").sortable({
        distance: 8,
        connectWith: ".sortable",
        items: "> li",
        cancel: '.wait',
        start: function() {
          sortableUpdate = false;
        },
        update: function() {
          sortableUpdate = true;
        },
        stop: function(event, ui) {
          if (sortableUpdate) {
            sortPlanning(event, ui);
          }
        }
      }).disableSelection();
      $(".route[data-route_id='" + route.route_id + "'] li[data-stop_id]")
        .mouseover(function() {
          $('span.number', this).css({
            display: 'none'
          });
          $('i.fa-reorder', this).css({
            display: 'inline-block'
          });
        })
        .mouseout(function() {
          $('i.fa-reorder', this).css({
            display: 'none'
          });
          $('span.number', this).css({
            display: 'inline-block'
          });
        })
        .each(function() {
          var $this = $(this);
          var stops = $.grep(route.stops, function(e) { return e.stop_id === $this.data('stop_id'); });
          if (stops.length > 0) {
            var stopData = $.extend(stops[0], {
              number: $('.number', $this).text(),
              i18n: mustache_i18n,
              planning_id: data.planning_id,
              routes: routesWithVehicle,
              route_id: route.route_id,
              vehicle_name: route.vehicle && route.vehicle.name,
              popover: true,
              manage_organize: true,
              manage_destination: true,
              manage_store: false
            });

            $this.popover({
              content: SMT['stops/show'](stopData),
              html: true,
              placement: 'auto',
              trigger: 'manual',
              viewport: {
                selector: '.sidebar-content',
                padding: 20
              }
            });

            $('.close-popover').click(function() {
              $(lastPopover).popover('hide');
            });
          }
        })
        .click(function() {
          // Stack the last element activated
          lastPopover = $(this);
          $("li[data-stop_id!='" + $(this).data('stop_id') + "']").popover('hide');
          $(this).popover($('.sidebar').hasClass('extended') ? 'toggle' : 'hide');
          $('.close-popover').click(function() {
            $(lastPopover).popover('hide');
          });
        });
    });

    $(document).keyup(function(event) {
      if ($(".sidebar").hasClass('extended') && event.keyCode === 27 && typeof lastPopover !== 'undefined') {
        $(lastPopover).popover('hide');
      }
    });

    dropdownAutoDirection($('#planning').find('[data-toggle="dropdown"]'));

    map.closePopup();

    checkLockAndActive();
  };

  // Update only stops by default
  var updatePlanning = function(data, options) {
    displayPlanning(data, $.extend({
      partial: 'stops'
    }, options));
  };

  function automaticInsertStops(stop_ids, options) {
    $.ajax($.extend({
      url: '/plannings/' + planning_id + '/automatic_insert',
      type: 'PATCH',
      dataType: 'json',
      data: {
        stop_ids: stop_ids
      },
      beforeSend: beforeSendWaiting,
      complete: completeAjaxMap,
      error: ajaxError,
      success: updatePlanning
    }, options));
  }

  $(".main").on("click", ".automatic_insert", function() {
    var stop_id = $(this).closest("[data-stop_id]").attr("data-stop_id");

    var dialog = bootstrap_dialog($.extend(modal_options(), {
      title: I18n.t('plannings.edit.dialog.automatic_insert.title'),
      message: SMT['modals/default_with_progress']({
        msg: I18n.t('plannings.edit.dialog.automatic_insert.in_progress')
      })
    })).modal({
      keyboard: false,
      show: true
    });
    automaticInsertStops([stop_id], {
      complete: function() {
        dialog.modal('hide');
        completeAjaxMap();
      },
      success: function(data) {
        updatePlanning(data);
        enlightenStop({id: stop_id});
        map.closePopup();
      }
    });
  });

  $(".main").on("click", ".automatic_insert_all", function() {
    if ($('#out_of_route > li').length > 20) {
      alert(I18n.t('plannings.edit.automatic_insert_too_many'));
      return false;
    }
    if (confirm(I18n.t('plannings.edit.automatic_insert_confirm'))) {
      var dialog = bootstrap_dialog($.extend(modal_options(), {
        title: I18n.t('plannings.edit.dialog.automatic_insert.title'),
        message: SMT['modals/default_with_progress']({
          msg: I18n.t('plannings.edit.dialog.automatic_insert.in_progress')
        })
      })).modal({
        keyboard: false,
        show: true
      });
      automaticInsertStops([], {
        complete: function() {
          dialog.modal('hide');
          completeAjaxMap();
          map.closePopup();
        }
      });
    }
  });

  $(".main").on('change', 'input:checkbox.stop_active', function(event) {
    var route_id = $(event.target).closest("[data-route_id]").attr("data-route_id");
    var stop_id = $(event.target).closest("[data-stop_id]").attr("data-stop_id");
    var active = $(event.target).is(':checked');
    $.ajax({
      type: 'PATCH',
      data: JSON.stringify({
        stop: {
          active: active
        }
      }),
      contentType: 'application/json',
      url: '/plannings/' + planning_id + '/' + route_id + '/' + stop_id + '.json',
      beforeSend: beforeSendWaiting,
      success: updatePlanning,
      complete: completeAjaxMap,
      error: ajaxError
    });
  });

  $(".main").on("click", ".send_to_route", function() {
    var stopId = $(this).closest("[data-stop_id]").attr("data-stop_id");
    var url = this.href;
    $.ajax({
      type: 'PATCH',
      url: url,
      beforeSend: beforeSendWaiting,
      success: function(data) {
        updatePlanning(data);
        enlightenStop({id: stopId});
        map.closePopup();
      },
      complete: completeAjaxMap,
      error: ajaxError
    });
    return false;
  });

  var displayPlanningFirstTime = function(data) {
    displayPlanning(data, {
      firstTime: true
    });
  };

  var checkForDisplayPlanningFirstTime = function(data) {
    if (data.outdated) {

      var displayPlanningAfterModal = function() {
        var cursorBody = $('body').css('cursor');
        var cursorMap = $('#map').css('cursor');
        $('body, #map').css({
          cursor: 'progress'
        });
        setTimeout(function() {
          displayPlanningFirstTime(data);
          $('body').css({
            cursor: cursorBody
          });
          $('#map').css({
            cursor: cursorMap
          });
        }, 100);
      };

      $('#planning-refresh-modal').modal({
        keyboard: true,
        show: true
      });
      $("#refresh-modal").click(function() {
        $('#planning-refresh-modal').off('hidden.bs.modal', displayPlanningAfterModal);
        $('#planning-refresh-modal').modal('hide');
        $.ajax({
          type: 'GET',
          url: '/plannings/' + planning_id + '/refresh.json?with_stops=' + withStopsInSidePanel,
          beforeSend: beforeSendWaiting,
          success: displayPlanningFirstTime,
          complete: completeAjaxMap,
          error: ajaxError
        });
      });
      $('#planning-refresh-modal').on('hidden.bs.modal', displayPlanningAfterModal);
    } else {
      displayPlanningFirstTime(data);
    }
  };

  $('.btn.extend').click(function() {
    $('.sidebar').toggleClass('extended');
    if ($('.sidebar').hasClass('extended')) {
      $(".routes").sortable("enable");
    } else {
      $(".routes").sortable("disable");
    }
  });

  $.ajax({
    url: '/plannings/' + planning_id + '.json?with_stops=' + withStopsInSidePanel,
    beforeSend: beforeSendWaiting,
    success: checkForDisplayPlanningFirstTime,
    complete: completeAjaxMap,
    error: ajaxError
  });

  if (zoning_ids && zoning_ids.length > 0) {
    $.each(zoning_ids, function(i, zoningId) {
      $.ajax({
        type: 'GET',
        url: "/api/0.1/zonings/" + zoningId + ".json",
        beforeSend: beforeSendWaiting,
        success: displayZoning,
        complete: completeAjaxMap,
        error: ajaxError
      });
    });
  }

  $('#isochrone_size').timeEntry({
    show24Hours: true,
    spinnerImage: '',
    defaultTime: '00:00'
  });

  $('#isochrone').click(function() {
    var vehicle_usage_id = $('#isochrone_vehicle_usage_id').val();
    var size = $('#isochrone_size').val().split(':');
    size = parseInt(size[0]) * 3600 + parseInt(size[1]) * 60;

    $.ajax({
      url: '/api/0.1/zonings/isochrone',
      type: 'PATCH',
      dataType: "json",
      data: {
        vehicle_usage_id: vehicle_usage_id,
        size: size,
        lat: $('#isochrone_lat').val(),
        lng: $('#isochrone_lng').val()
      },
      beforeSend: function() {
        beforeSendWaiting();
        $('#isochrone-modal').modal('hide');
        $('#isochrone-progress-modal').modal({
          backdrop: 'static',
          keyboard: true
        });
      },
      success: function(data) {
        hideNotices();
        fitBounds = true;
        displayZoning(data);
        map.closePopup();
        notice(I18n.t('zonings.edit.success'));
      },
      complete: function() {
        completeAjaxMap();
        $('#isochrone-progress-modal').modal('hide');
      },
      error: function() {
        stickyError(I18n.t('zonings.edit.failed'));
      }
    });
  });

  $('#isodistance').click(function() {
    var vehicle_usage_id = $('#isodistance_vehicle_usage_id').val();
    var size = $('#isodistance_size').val() * 1000;
    $('#isodistance-progress-modal').modal({
      backdrop: 'static',
      keyboard: true
    });
    $('#isodistance-modal').modal('hide');
    $.ajax({
      type: 'PATCH',
      url: '/api/0.1/zonings/isodistance.json',
      dataType: "json",
      data: {
        vehicle_usage_id: vehicle_usage_id,
        size: size,
        lat: $('#isodistance_lat').val(),
        lng: $('#isodistance_lng').val()
      },
      beforeSend: beforeSendWaiting,
      success: function(data) {
        fitBounds = true;
        displayZoning(data);
        map.closePopup();
      },
      complete: function() {
        completeAjaxMap();
        $('#isodistance-progress-modal').modal('hide');
      },
      error: ajaxError
    });
  });

  spreadsheetModalExport(params.spreadsheet_columns, params.planning_id);
};

var plannings_show = function(params) {
  'use strict';

  if (!params.print_map) {
    window.print();
  } else {
    $('.btn-print').click(function() {
      window.print();
    });
  }
};

var plannings_index = function(params) {
  'use strict';

  iCalendarExport();
  spreadsheetModalExport(params.spreadsheet_columns);
};

var devicesObservePlanning = (function() {
  'use strict';

  var _context;

  var _setLastSentAt = function(route) {
    var container = $("[data-route_id='" + route.id + "'] .last-sent-at", _context);
    route.i18n = mustache_i18n;
    container.html(SMT['routes/last_sent_at'](route));
    route.last_sent_at ? container.show() : container.hide();
  };

  var _setPlanningRoutesLastSentAt = function(routes) {
    $.each(routes, function(i, route) {
      _setLastSentAt(route);
    });
  };

  var _clearLastSentAt = function(route) {
    $("[data-route_id='" + route.id + "'] .last-sent-at", _context).hide();
  };

  var _clearPlanningRoutesLastSentAt = function(routes) {
    $.each(routes, function(i, route) {
      _clearLastSentAt(route);
    });
  };

  var _devicesInitVehicle = function(callback) {

    $.each($('.last-sent-at', _context), function(i, element) {
      if ($(element).find('span').html() === '') $(element).hide();
    });

    // Still needed, maybe ask to FLO why ?!
    $(_context).off('click', '.device-operation').on('click', '.device-operation', function(e) {
      if (!confirm(I18n.t('all.verb.confirm'))) return;

      var from = $(e.target),
        service = from.data('service'),
        operation = from.data('operation'),
        url = '/api/0.1/devices/' + service + '/' + operation,
        data = {};

      var service_translation = 'plannings.edit.dialog.' + service + '.in_progress';
      var dialog = bootstrap_dialog({
        icon: 'fa-bars',
        title: service && service.substr(0, 1).toUpperCase() + service.substr(1),
        message: SMT['modals/default_with_progress']({
          msg: I18n.t(service_translation)
        })
      });

      if (from.data('planning-id')) data.planning_id = from.data('planning-id');
      if (from.data('route-id')) data.route_id = from.data('route-id');
      if (from.data('type')) data.type = from.data('type');

      $.ajax({
        url: url + (data.planning_id ? '_multiple' : ''),
        type: (operation === 'clear') ? 'DELETE' : 'POST',
        dataType: 'json',
        data: data,
        beforeSend: function() {
          dialog.modal('show');
        },
        success: function(data) {
          if (data && data.error) {
            stickyError(data.error);
          } else {
            var service_translation = 'plannings.edit.' + service + '_' + operation + (from.data('type') ? '_' + from.data('type') : '') + '.success';
            notice(I18n.t(service_translation));

            if (from.data('planning-id') && operation === 'send')
              _setPlanningRoutesLastSentAt(data);
            else if (from.data('planning-id') && operation === 'clear')
              _clearPlanningRoutesLastSentAt(data);
            else if (from.data('route-id') && operation === 'send')
              _setLastSentAt(data);
            else if (from.data('route-id') && operation === 'clear')
              _clearLastSentAt(data, _context);

            callback && callback(from); // for backgroundTask
          }
        },
        complete: function() {
          dialog.modal('hide');
        },
        error: function() {
          var service_error_translation = 'plannings.edit.' + service + '_' + operation + (from.data('type') ? '_' + from.data('type') : '') + '.fail';
          stickyError(I18n.t(service_error_translation));
        }
      });

      // Reset Dropdown
      $(this).closest(".dropdown-menu").prev().dropdown("toggle");
      return false;
    });
  };

  var init = function(context, callback) {
    _context = context;
    _devicesInitVehicle(callback);
  };

  return { init: init };

})();

Paloma.controller('Plannings', {
  index: function() {
    plannings_index(this.params);
  },
  new: function() {
    plannings_new(this.params);
  },
  create: function() {
    plannings_new(this.params);
  },
  edit: function() {
    plannings_edit(this.params);
  },
  update: function() {
    plannings_edit(this.params);
  },
  show: function() {
    plannings_show(this.params);
  }
});
