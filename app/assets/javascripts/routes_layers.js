// Copyright © Mapotempo, 2017
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

/******************
 * PopupModule
 *
 */
var popupModule = (function() {
  'use strict';

  var _context,
    _previousMarker,
    _activeClickMarker,
    _previousPopup,
    _currentAjaxRequested,
    _ajaxTimer = 100;

  var _ajaxCanBeProceeded = function() {
    var currentTime = (!Date.now) ? (new Date().getTime()) : Date.now(); // Ensure IE <9 compatibility
    if ((currentTime - _ajaxTimer) >= 100) {
      _ajaxTimer = currentTime;
      return true;
    }
    return false;
  };

  var _buildContentForPopup = function(marker, map) {

    var route = marker.properties.route_id && _context.options.routes.filter(function(route) {
      return route.route_id == marker.properties.route_id;
    })[0];
    if (route && route.outdated) {
      marker.bindPopup(L.responsivePopup({
        offset: marker.options.icon.options.iconSize.divideBy(2)
      }).setContent(I18n.t('plannings.edit.popup.outdated')), {
        minWidth: 200,
        autoPan: false,
        closeOnClick: false
      }).getPopup();
      _previousPopup = marker.getPopup();
      marker.openPopup();
    }
    else {
      if (_ajaxCanBeProceeded()) {
        var url = _context.options.appBaseUrl;

        if (_context.planningId) {
          url += (marker.properties.store_id) ?
            'stores/' + marker.properties.store_id + '.json' :
            'routes/' + marker.properties.route_id + '/stops/by_index/' + marker.properties.index + '.json';
        } else {
          url += 'visits/' + marker.properties.visit_id + '.json';
        }

        getPopupContent(url, marker, map);

        _currentAjaxRequested.done(function() {
          _previousPopup = marker.getPopup();
          marker.openPopup();
        });
      }
    }
  };

  var getPopupContent = function(url, marker, map) {
    if (marker.getPopup())
      return;

    if (_currentAjaxRequested && _currentAjaxRequested.readyState !== 4)
      return;

    _currentAjaxRequested = $.ajax({
      url: url,
      beforeSend: beforeSendWaiting,
      success: function(data) {
        var popup = marker.bindPopup(L.responsivePopup({
          offset: marker.options.icon.options.iconSize.divideBy(2)
        }), {
          minWidth: 200,
          autoPan: false,
          closeOnClick: false
        }).addTo(map).getPopup();

        data.i18n = mustache_i18n;
        data.routes = _context.options.routes.filter(function(route) { return route.vehicle_usage_id; } ); // unnecessary to load all for each stop
        data.out_of_route_id = _context.options.outOfRouteId;
        data.number = marker.properties.number;
        if (marker.properties.tomtom) {
          data.tomtom = marker.properties.tomtom;
        }
        if (_context.options.url_click2call) {
          phoneNumberCall(data, _context.options.url_click2call);
        }
        $.extend(data, _context.options.popupOptions);
        popup.setContent(SMT['stops/show'](data));

        $('#isochrone_lat').val(data.lat);
        $('#isochrone_lng').val(data.lng);
        $('#isochrone_vehicle_usage_id').val(data.vehicle_usage_id);
        $('#isodistance_lat').val(data.lat);
        $('#isodistance_lng').val(data.lng);
        $('#isodistance_vehicle_usage_id').val(data.vehicle_usage_id);
      },
      complete: completeAjaxMap,
      error: ajaxError
    });
  };

  var createPopupForLayer = function(layer, map) {
    if (_previousMarker)
      _previousMarker.closePopup();

    if (_previousPopup instanceof L.Popup)
      _previousPopup.closePopup();

    _buildContentForPopup(layer, map);
  };

  var initializeModule = function(options, that) {
    _context = that;
  };

  return {
    initGlobal: initializeModule,
    getPopupContent: getPopupContent,
    createPopupForLayer: createPopupForLayer,

    // PreviousMarker setter/getter
    get previousMarker() {
      return _previousMarker;
    },
    set previousMarker(value) {
      if (value instanceof L.Marker) {
        if (_previousMarker !== value) _previousMarker = value;
      } else {
        throw Error("Only Markers can be set in this variable");
      }
    },

    // activeClickMarker setter/getter
    get activeClickMarker() {
      return _activeClickMarker;
    },
    set activeClickMarker(value) {
      if (_activeClickMarker !== value) _activeClickMarker = value;
    },

    // Previous popup setter/getter
    get previousPopup() {
      return _previousPopup;
    },
    set previousPopup(value) {
      if (_previousPopup !== value && _previousMarker instanceof Object)
        _previousPopup = value;
    }

  };

})();

function markerClusterIcon(childCount, defaultColor, borderColors) {
  var totalCountColors = 0;
  for (var colorCount in borderColors) {
    totalCountColors += borderColors[colorCount];
  }

  L.Icon.MarkerCluster = L.Icon.extend({
    options: {
      iconSize: new L.Point(36, 36),
      className: 'marker-cluster-multi-color leaflet-markercluster-icon'
    },
    createIcon: function() {
      var canvas = document.createElement('canvas');
      this._setIconStyles(canvas, 'icon');
      var iconSize = this.options.iconSize;
      canvas.width = iconSize.x;
      canvas.height = iconSize.y;
      this.draw(canvas.getContext('2d'), iconSize.x, iconSize.y);
      return canvas;
    },
    createShadow: function() {
      return null;
    },
    draw: function(canvas, width, height) {
      var borderSize = 6;
      var halfSize = width / 2 | 0;
      var start = 0;
      for (var colorValue in borderColors) {
        var size = borderColors[colorValue] / totalCountColors;

        if (size > 0) {
          canvas.beginPath();
          canvas.moveTo(halfSize, halfSize);
          canvas.fillStyle = colorValue;
          var from = start;
          if (Object.keys(borderColors).length > 1) {
            from += 0.06;
          }
          var to = start + size * Math.PI * 2;
          if (to < from) {
            from = start;
          }
          canvas.arc(halfSize, halfSize, halfSize, from, to);
          start = start + size * Math.PI * 2;
          canvas.lineTo(halfSize, halfSize);
          canvas.fill();
          canvas.closePath();
        }
      }
      canvas.beginPath();
      canvas.fillStyle = defaultColor;
      canvas.arc(halfSize, halfSize, halfSize - borderSize, 0, Math.PI * 2);
      canvas.fill();
      canvas.closePath();
      canvas.fillStyle = 'white';
      canvas.textAlign = 'center';
      canvas.textBaseline = 'middle';
      canvas.font = '12px "Helvetica Neue", Arial, Helvetica, sans-serif';
      canvas.fillText(childCount, halfSize, halfSize, halfSize * 2 - borderSize);
    }
  });

  return new L.Icon.MarkerCluster();
}

var nbRoutes = 0;
function clusterRadiusByZoomAndRoute (currentZoom, nbRoutes) {
  return currentZoom > defaultMapZoom ? 1 : nbRoutes < 4 ? 30 * nbRoutes : 100
}

var RoutesLayer = L.FeatureGroup.extend({
  defaultOptions: {
    outOfRouteId: undefined,
    routes: [],
    colorsByRoute: {},
    isochrone: false,
    isodistance: false,
    url_click2call: undefined,
    unit: 'km',
    appBaseUrl: '/',
    withPolylines: true,
    withQuantities: false,
    disableClusters: false,
    showPopupOnHover: true
  },

  // Clusters for each route
  clustersByRoute: {},

  // Markers for each store
  markerStores: [],

  // Marker options
  markerOptions: {
    showCoverageOnHover: false,
    spiderfyOnMaxZoom: true,
    animate: false,
    maxClusterRadius: function(currentZoom) {
      // Markers have to be clustered during map initialization with defaultMapZoom
      return clusterRadiusByZoomAndRoute(currentZoom, nbRoutes);
    },
    spiderfyDistanceMultiplier: 0.5,
    // Updated in initialize
    // disableClusteringAtZoom: 12,
    iconCreateFunction: function(cluster) {
      if (cluster._map.getZoom() > cluster._map.defaultMapZoom) {
        var markers = cluster.getAllChildMarkers();
        var n = ['…'];
        var color;
        if (markers.length > 50) {
          color = markers[0].properties.color;
        } else {
          var colors = {};
          var max = 0;
          for (var i = 0; i < markers.length; i++) {
            var count = colors[markers[i].properties.color] ? colors[markers[i].properties.color] + 1 : 1;
            if (count > max) {
              max = count;
              color = markers[i].properties.color;
            }
          }
        }

        return new L.divIcon({
          html: '<span class="fa-stack"><i class="fa fa-circle cluster-point-border" style="color: ' + color + ';"></i><i class="fa fa-circle cluster-point-icon" style="color: \' + color + \';"></i><span class="fa-stack-1x point-icon-text cluster-point-text">' + n.join(',') + '</span></span>',
          iconSize: new L.Point(24, 24),
          iconAnchor: new L.Point(12, 12),
          className: 'cluster-icon-container'
        });
      } else {
        var useCanvasIcon = false;
        var childCount = cluster.getChildCount();
        var routeColor = cluster.getAllChildMarkers()[0].properties.route_color || '#707070';
        var countByColor = {};
        cluster.getAllChildMarkers().forEach(function(childMarker) {
          if (!countByColor[childMarker.properties.color]) {
            countByColor[childMarker.properties.color] = 1;
          } else {
            countByColor[childMarker.properties.color] += 1;
          }

          if (childMarker.properties.color !== routeColor) {
            useCanvasIcon = true;
          }
        });

        if (useCanvasIcon) {
          return markerClusterIcon(childCount, routeColor, countByColor);
        } else {
          return new L.DivIcon({
            html: '<div class="marker-cluster-icon" style="background-color: ' + routeColor + ';"><span>' + childCount + '</span></div>',
            className: 'marker-cluster marker-cluster-small',
            iconSize: new L.Point(40, 40)
          });
        }
      }
    }
  },

  initialize: function(planningId, options) {
    popupModule.initGlobal(null, this);
    L.FeatureGroup.prototype.initialize.call(this);
    this.planningId = planningId;
    this.options = $.extend({}, this.defaultOptions, options); // Don't modify defaultOptions which can be reinitialized by turbolinks

    if (this.options.disableClusters) {
      this.markerOptions.disableClusteringAtZoom = this.options.disableClusters ? 0 : 19;
    }

    // Clear layers if page is reloaded with turbolinks
    // this.hideAllRoutes();
  },

  onAdd: function(map) {
    L.FeatureGroup.prototype.onAdd.call(this, map);
    this.layersByRoute = {};
    this.map = map;
    this.map.on('click', this.hideLastPopup).on('zoomstart', this.hideLastPopup);

    this.on('mouseover', function(e) {
      if (this.options.showPopupOnHover) {
        if (e.layer instanceof L.Marker && !popupModule.activeClickMarker) {
          // Unbind pop when needed | != compare memory address between marker objects (Very same instance equality).

          if (popupModule.previousMarker && (popupModule.previousMarker != e.layer))
            popupModule.previousMarker.closePopup();

          if (e.layer.click)
            e.layer.click = false; // Don't forget to re-init e.layer.click

          popupModule.createPopupForLayer(e.layer, this.map);
        } else if (e.layer instanceof L.Path) {
          e.layer.setStyle({
            opacity: 0.9,
            weight: 7
          });
        }
      }
    }.bind(this)).on('mouseout', function(e) {
      if (this.options.showPopupOnHover) {
        if (e.layer instanceof L.Marker) {
          popupModule.previousMarker = e.layer;
          if (!e.layer.click && e.layer.getPopup()) {
            e.layer.closePopup();
          }
        } else if (e.layer instanceof L.Path) {
          e.layer.setStyle({
            opacity: 0.5,
            weight: 5
          });
        }
      }
    }.bind(this))
      .on('click', function(e) {
        // Open popup if only one is actually in a click statement.
        if (e.layer instanceof L.Marker) {
          if (e.layer.properties.index) {
            this.fire('clickStop', {
              index: e.layer.properties.index,
              routeId: e.layer.properties.route_id
            });
          }
          if (e.layer.click && (e.layer === popupModule.activeClickMarker)) {
            e.layer.closePopup();
            e.layer.click = false;
          } else {
            if (popupModule.activeClickMarker && e.layer !== popupModule.activeClickMarker) {
              popupModule.activeClickMarker.click = false;
              popupModule.activeClickMarker.closePopup();
              popupModule.createPopupForLayer(e.layer, this.map);
            } else if (popupModule.previousPopup) {
              e.layer.bindPopup(popupModule.previousPopup.addTo(map));
            }
            e.layer.click = true;
            popupModule.activeClickMarker = e.layer;
          }
        } else if (e.layer instanceof L.Path) {
          var content = '';

          var route = (e.layer.properties.route_id != this.options.outOfRouteId) && this.options.routes.filter(function(route) {
            return route.route_id == e.layer.properties.route_id;
          })[0];
          if (route && route.outdated) {
            content = I18n.t('plannings.edit.popup.outdated');
          }
          else {
            var distance = e.layer.properties.distance / 1000;
            var driveTime = e.layer.properties.drive_time;
            distance = (this.options.unit === 'km') ? distance.toFixed(1) + ' km' : (distance / 1.609344).toFixed(1) + ' miles';

            if (driveTime) {
              var driveTimeDay = null;
              if (driveTime > 3600 * 24) {
                driveTimeDay = driveTime / (3600 * 24) | 0;
              }
              driveTime = ('0' + parseInt(driveTime / 3600) % 24).slice(-2) + ':' + ('0' + parseInt(driveTime / 60) % 60).slice(-2) + ':' + ('0' + (driveTime % 60)).slice(-2);
              if (driveTimeDay) {
                driveTime += ' (' + I18n.t('plannings.edit.popup.day') + driveTimeDay + ')';
              }
            } else {
              driveTime = '';
            }
            content = (driveTime ? '<div>' + I18n.t('plannings.edit.popup.stop_drive_time') + ' ' + driveTime + '</div>' : '') + '<div>' + I18n.t('plannings.edit.popup.stop_distance') + ' ' + distance + '</div>';
          }

          L.responsivePopup({
            minWidth: 200,
            autoPan: false,
            closeOnClick: true
          }).setLatLng(e.latlng).setContent(content).openOn(this.map);
        }
      }.bind(this))
      .on('popupopen', function(e) {
        // Silence is golden
      }.bind(this))
      .on('popupclose', function(e) {
        // Silence is golden
        e.layer.unbindPopup();
        popupModule.activeClickMarker = void(0);
      }.bind(this));
  },

  hideLastPopup: function() {
    if (popupModule.previousPopup) {
      this.removeLayer(popupModule.previousPopup);
      popupModule.previousPopup = null;
    }
  },

  showRoutes: function(routeIds, geojson, callback) {
    this._load(routeIds, false, geojson, callback);
  },

  showRoutesWithStore: function(routeIds, geojson, callback) {
    this._load(routeIds, true, geojson, callback);
  },

  hideRoutes: function(routeIds) {
    this._removeRoutes(routeIds);
  },

  refreshRoutes: function(routeIds, geojson) {
    this._removeRoutes(routeIds);
    // FIXME: callback could be used to avoid blink
    this.showRoutes(routeIds, geojson);
  },

  showAllRoutes: function(options, callback) {
    this.hideAllRoutes();
    this._loadAll(options, callback);
  },

  hideAllRoutes: function() {
    this.clearLayers();
    this.layersByRoute = {};
    this.clustersByRoute = {};
  },

  switchMarkerClusters: function() {
    var cursorBody = $('body').css('cursor');
    $('body').css('cursor', 'pointer');

    this.options.disableClusters = !this.options.disableClusters;

    var newClustersByRoute = {};

    nbRoutes = Object.keys(this.clustersByRoute).length;
    for (var routeId in this.clustersByRoute) {
      if (this.clustersByRoute.hasOwnProperty(routeId)) {
        // this.markerOptions.disableClusteringAtZoom = this.options.disableClusters ? 0 : 19;

        this.markerOptions.maxClusterRadius = function(currentZoom) {
          if (this.options.disableClusters) {
            return 1;
          } else {
            return clusterRadiusByZoomAndRoute(currentZoom, nbRoutes);
          }
        }.bind(this);

        newClustersByRoute[routeId] = L.markerClusterGroup(this.markerOptions);

        this.clustersByRoute[routeId].getLayers().forEach(function (routeId, marker) {
          newClustersByRoute[routeId].addLayer(marker);
        }.bind(this, routeId));

        this.removeLayer(this.clustersByRoute[routeId]);
        this.clustersByRoute[routeId] = undefined;

        this.addLayer(newClustersByRoute[routeId]);

        this.clustersByRoute[routeId] = newClustersByRoute[routeId];
      }
    }

    $('body').css('cursor', cursorBody);
  },

  focus: function(options) {
    if (options.routeId && options.stopIndex) {
      if (this.clustersByRoute[options.routeId]) {
        var markers = this.clustersByRoute[options.routeId].getLayers();
        for (var i = 0; i < markers.length; i++) {
          if (markers[i].properties['index'] == options.stopIndex) {
            this._setViewForMarker(options.routeId, markers[i]);
            break;
          }
        }
      }
    } else if (options.storeId) {
      for (var i = 0; i < this.markerStores.length; i++) {
        if (this.markerStores[i].properties['store_id'] == options.storeId) {
          this.map.setView(this.markerStores[i].getLatLng(), this.map.getZoom(), {
            reset: true
          });
          popupModule.createPopupForLayer(this.markerStores[i], this.map);
          break;
        }
      }
    }
  },

  togglePopupOnHover: function() {
    this.options.showPopupOnHover = !this.options.showPopupOnHover;
  },

  _setViewForMarker: function(routeId, marker) {
    this.map.closePopup();

    if (!this.clustersByRoute[routeId].hasLayer(marker)) {
      marker.addTo(this.clustersByRoute[routeId]);
    }

    if (this.map.getBounds().contains(marker.getLatLng()) && marker._map) {
      // _map is actually undefined or null (markerCluster set it on clustered markers)
      popupModule.createPopupForLayer(marker, this.map);
      popupModule.activeClickMarker = marker;
    } else {
      this.map.setView(this.map.getCenter(), this.map.getMaxZoom(), {animate: false, duration: 0});
      this.clustersByRoute[routeId].zoomToShowLayer(marker, function() {
        popupModule.createPopupForLayer(marker, this.map);
        popupModule.activeClickMarker = marker;
      }.bind(this));
    }
  },

  _load: function(routeIds, includeStores, geojson, callback) {
    if (!geojson) {
      $.ajax({
        url: '/api/0.1/plannings/' + this.planningId + '/routes.geojson?geojson=' + (this.options.withPolylines ? 'polyline' : 'point') + '&ids=' + routeIds.join(',') + '&stores=' + includeStores,
        beforeSend: beforeSendWaiting,
        success: function(data) {
          this._addRoutes(data);
          if (typeof callback === 'function') {
            callback();
          }
        }.bind(this),
        complete: completeAjaxMap,
        error: ajaxError
      });
    } else {
      this._addRoutes(geojson);
      if (typeof callback === 'function') {
        callback();
      }
    }
  },

  _loadAll: function(options, callback) {
    var requestData = options || {};
    requestData.quantities = this.options.withQuantities;
    if (this.planningId) {
      requestData.geojson = this.options.withPolylines ? 'polyline' : 'point';
    }

    $.ajax({
      url: this.planningId ? '/api/0.1/plannings/' + this.planningId + '.geojson' : '/api/0.1/visits.geojson',
      data: requestData,
      beforeSend: beforeSendWaiting,
      success: function(data) {
        this._addRoutes(data);
        if (typeof callback === 'function') {
          callback();
        }
      }.bind(this),
      complete: completeAjaxMap,
      error: ajaxError
    });
  },

  _addRoutes: function(geojson) {
    var overlappingMarkers = {};

    var globalLayer = L.geoJSON(geojson, {
      filter: function(feature) {
        if (feature.geometry.polylines) {
          feature.geometry.coordinates = L.PolylineUtil.decode(feature.geometry.polylines, 6); // precision
          for (var j = 0; j < feature.geometry.coordinates.length; j++) {
            feature.geometry.coordinates[j] = [feature.geometry.coordinates[j][1], feature.geometry.coordinates[j][0]];
          }
          delete feature.geometry.polylines;
        }
        return true;
      },
      onEachFeature: function(feature, layer) {
        if (feature.properties.route_id) {
          if (!(feature.properties.route_id in this.layersByRoute)) {
            this.layersByRoute[feature.properties.route_id] = [];
          }
          this.layersByRoute[feature.properties.route_id].push(layer);
        } else if (feature.properties.store_id) {
          this.layerStores = layer;
        }
        layer.properties = feature.properties;
      }.bind(this),
      style: function(feature) {
        return {
          color: feature.properties.color,
          opacity: 0.5,
          weight: 5
        };
      }.bind(this),
      pointToLayer: function(geoJsonPoint, latlng) {
        var icon;
        var overlapKey = latlng.lat.toString() + '-' + latlng.lng.toString();

        var storeId = geoJsonPoint.properties.store_id;
        var routeId = geoJsonPoint.properties.route_id;

        // map.iconSize is defined in scaffold file
        if (storeId) {
          var storeIcon = geoJsonPoint.properties.icon || 'fa-home';
          var storeIconSize = geoJsonPoint.properties.icon_size || 'large';
          var storeColor = geoJsonPoint.properties.color || 'black';
          icon = L.divIcon({
            html: '<i class="fa ' + storeIcon + ' ' + this.map.iconSize[storeIconSize].name + ' store-icon" style="color: ' + storeColor + ';"></i>',
            iconSize: new L.Point(this.map.iconSize[storeIconSize].size, this.map.iconSize[storeIconSize].size),
            iconAnchor: new L.Point(this.map.iconSize[storeIconSize].size / 2, this.map.iconSize[storeIconSize].size / 2),
            className: 'store-icon-container'
          });
        } else {
          var radius, baseAngle, baseMultiplier = 6, baseModulo = 1, lowIndex = false;

          var pointIcon = geoJsonPoint.properties.icon || 'fa-circle';
          var pointIconSize = geoJsonPoint.properties.icon_size || 'medium';
          var pointColor = geoJsonPoint.properties.color || '#707070';
          if (!geoJsonPoint.properties.number)
            pointColor = 'rgba(' + parseInt(pointColor.substring(1, 3), 16) + ',' + parseInt(pointColor.substring(3, 5), 16) + ',' + parseInt(pointColor.substring(5, 7), 16) + ',0.8)';
          var pointAnchor = new L.Point(this.map.iconSize[pointIconSize].size / 2, this.map.iconSize[pointIconSize].size / 2);

          if (overlappingMarkers[overlapKey]) {
            if (overlappingMarkers.routeIds.indexOf(routeId) === -1 || this.options.disableClusters) {
              var cycleSize = overlappingMarkers[overlapKey] === (baseMultiplier * Math.pow(overlappingMarkers.modulo, 2));

              if ((overlappingMarkers[overlapKey] % overlappingMarkers.multiplier) === 0 && cycleSize) {
                overlappingMarkers.modulo++;
                overlappingMarkers.multiplier *= overlappingMarkers.modulo;
              }

              radius = 13 * overlappingMarkers.modulo;
              baseAngle = 10 * overlappingMarkers.modulo;

              var x = radius * Math.cos(baseAngle * overlappingMarkers[overlapKey]);
              var y = radius * Math.sin(baseAngle * overlappingMarkers[overlapKey]);

              var reducer = this.map.iconSize[pointIconSize].size / 2;
              pointAnchor = new L.Point(x + reducer, y + reducer);

              overlappingMarkers[overlapKey]++;
              overlappingMarkers.routeIds.push(routeId);
              lowIndex = true;
            } else {
              // Reset values if same routes same posXY
              this.clustersByRoute[routeId].getLayers().forEach(function(marker) {
                var size = this.map.iconSize[pointIconSize].size / 2;
                marker.options.icon.options.iconAnchor = marker.options.icon.options.popupAnchor = L.Point(size, size);
              }.bind(this));
            }
          } else {
            overlappingMarkers[overlapKey] = 1;
            overlappingMarkers.modulo = baseModulo;
            overlappingMarkers.multiplier = baseMultiplier * overlappingMarkers.modulo;
            overlappingMarkers.routeIds = [];
          }

          var pAnchor = [-pointAnchor.x + this.map.iconSize[pointIconSize].size / 2, -pointAnchor.y + this.map.iconSize[pointIconSize].size / 2];

          icon = L.divIcon({
            html: '<span class="fa-stack" style="line-height: ' + this.map.iconSize[pointIconSize].size + 'px"><i class="fa ' + pointIcon + ' point-icon" style="color: ' + pointColor + ' !important; font-size: ' + this.map.iconSize[pointIconSize].size + 'px"></i><span class="fa-stack-1x point-icon-text">' + (geoJsonPoint.properties.number || '') + '</span></span>',
            iconSize: new L.Point(this.map.iconSize[pointIconSize].size, this.map.iconSize[pointIconSize].size),
            iconAnchor: pointAnchor,
            popupAnchor: pAnchor,
            className: 'point-icon-container'
          });
        }

        var marker = L.marker(new L.LatLng(latlng.lat, latlng.lng), {
          icon: icon
        });

        if (geoJsonPoint.properties.number) {
          (lowIndex) ? marker.setZIndexOffset(-999) : marker.setZIndexOffset(500);
        }

        marker.properties = geoJsonPoint.properties;
        // Add route color to each marker
        marker.properties.route_color = this.options.colorsByRoute[geoJsonPoint.properties.route_id];

        if (storeId) {
          this.markerStores.push(marker);
        } else {
          if (!this.clustersByRoute[routeId]) {
            this.clustersByRoute[routeId] = L.markerClusterGroup(this.markerOptions);
          }
          this.clustersByRoute[routeId].addLayer(marker);
        }
        // return marker; // Markers are already added in cluster, don't add to layer
      }.bind(this)
    });

    // Add only route polylines to map
    this.addLayer(globalLayer);

    // Add marker clusters
    nbRoutes = Object.keys(this.clustersByRoute).length;
    for (var routeId in this.clustersByRoute) {
      if (this.clustersByRoute.hasOwnProperty(routeId)) {
        this.addLayer(this.clustersByRoute[routeId]);
      }
    }

    // Add store markers
    for (var storeId in this.markerStores) {
      this.addLayer(this.markerStores[storeId]);
    }
  },

  _removeRoutes: function(routeIds) {
    routeIds.forEach(function(routeId) {
      if (routeId in this.layersByRoute) {
        this.layersByRoute[routeId].forEach(function(layer) {
          this.map.removeLayer(layer);
        }.bind(this));
        delete this.layersByRoute[routeId];
      }
      if (routeId in this.clustersByRoute) {
        this.removeLayer(this.clustersByRoute[routeId]);
        delete this.clustersByRoute[routeId];
      }
    }.bind(this));
    popupModule.activeClickMarker = false;
  }
});
