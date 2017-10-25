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

var customers_index = function(params) {
  'use strict';

  var map_layers = params.map_layers,
    map_attribution = params.map_attribution;

  var is_map_init = false;

  var map_init = function() {

    var map = mapInitialize(params);
    L.control.attribution({
      prefix: false
    }).addTo(map);

    var layer = L.featureGroup();
    map.addLayer(layer);


    function determineIconColor(customer) {

      var color = {
        isActiv: '558800', // green
        isNotActiv: '707070', // grey
        isTest: '0077A3' // blue
      };

      return customer.test ? color.isTest : (customer.isActiv ? color.isActiv : color.isNotActiv);

    }

    var display_customers = function(data) {

      $.each(data.customers, function(i, customer) {

        var iconImg = '/images/point-' + determineIconColor(customer) + '.svg';

        var marker = L.marker(new L.LatLng(customer.lat, customer.lng), {

          icon: new L.NumberedDivIcon({
            number: customer.max_vehicles,
            iconUrl: iconImg,
            iconSize: new L.Point(12, 12),
            iconAnchor: new L.Point(6, 6),
            popupAnchor: new L.Point(0, -6),
            className: "small"
          })

        }).addTo(layer).bindPopup(customer.name);

      });

      map.invalidateSize();

      if (layer.getLayers().length > 0) {
        map.fitBounds(layer.getBounds(), {
          maxZoom: 15,
          padding: [20, 20]
        });
      }

    };

    $.ajax({
      url: '/customers.json',
      beforeSend: beforeSendWaiting,
      success: display_customers,
      complete: completeWaiting,
      error: ajaxError
    });

  };

  $('#accordion').on('show.bs.collapse', function(event, ui) {
    if (!is_map_init) {
      is_map_init = true;
      map_init();
    }
  });
};

var customers_edit = function(params) {
  'use strict';

  /* Speed Multiplier */
  $('form.number-to-percentage').submit(function(e) {
    $.each($(e.target).find('input[type=\'number\'].number-to-percentage'), function(i, element) {
      var value = $(element).val() ? Number($(element).val()) / 100 : 1;
      $($(document.createElement('input')).attr('type', 'hidden').attr('name', 'customer[' + $(element).attr('name') + ']').val(value)).insertAfter($(element));
    });
    return true;
  });

  /* API: Devices */
  devicesObserveCustomer.init($.extend(params, {
    // FIXME -> THE DEFAULT PASSWORD MUST BE DONE AT THE BACKEND LVL, WICH MAKE NOT VISIBLE THE TRUE PASSWORD FROM DB
    default_password: Math.random().toString(36).slice(-8)
  }));

  $('#customer_end_subscription').datepicker({
    autoclose: true,
    calendarWeeks: true,
    todayHighlight: true,
    format: I18n.t("all.datepicker"),
    language: I18n.currentLocale(),
    zIndexOffset: 1000
  });

  $('#customer_take_over').timeEntry({
    show24Hours: true,
    showSeconds: true,
    initialField: 1,
    defaultTime: '00:00:00',
    spinnerImage: ''
  });

  var getLocaleFromCurrentLocale = function () {
    for (var locale in $.fn.wysihtml5.locale) {
      if (locale.indexOf(I18n.currentLocale()) !== -1) {
        return locale;
      }
    }
  };

  $('#customer_print_header').wysihtml5({
    locale: getLocaleFromCurrentLocale(),
    toolbar: {
      link: false,
      image: false,
      blockquote: false,
      size: 'sm',
      fa: true
    }
  });

  routerOptionsSelect('#customer_router', params);
};

var devicesObserveCustomer = (function() {
  'use strict';

  function _devicesInitCustomer(base_name, config, params) {
    var requests = [];

    function clearCallback() {
      $('.' + config.name + '-api-sync').attr('disabled', 'disabled');
      $('#' + config.name + '_container').removeClass('panel-success panel-danger').addClass('panel-default');
    }

    function successCallback() {
      $('.' + config.name + '-api-sync').removeAttr('disabled');
      $('#' + config.name + '_container').removeClass('panel-default panel-danger').addClass('panel-success');
    }

    // maybe need rework on this one - WARNING -
    function errorCallback(apiError) {
      stickyError(apiError);
      $('.' + config.name + '-api-sync').attr('disabled', 'disabled');
      $('#' + config.name + '_container').removeClass('panel-default panel-success').addClass('panel-danger');
    }

    function _userCredential() {
      var hash = {};
      $.each(config.forms.settings, function(key, type) {
        hash[key] = $('#' + base_name + '_' + config.name + '_' + key).val() || void(0);
        if (key == 'password' && hash[key] == params.default_password)
          hash[key] = void(0);
      });
      return hash;
    }

    function _allFieldsFilled() {
      var isNotEmpty = true;
      var inputs = $('input[type="text"], input[type="password"]', '#' + config.name + '_container');
      inputs.each(function() {
        if ($(this).val() == '')
          isNotEmpty = false;
      });
      return inputs.length && isNotEmpty ? true : false;
    }

    function _ajaxCall(all) {
      $.when($(requests)).done(function() {
        if (!_allFieldsFilled()) return;
        requests.push($.ajax({
          url: '/api/0.1/devices/' + config.name + '/auth/' + params.customer_id + '.json',
          data: (all) ? _userCredential() : $.extend(_userCredential(), {
            check_only: 1
          }),
          dataType: 'json',
          beforeSend: function(jqXHR, settings) {
            if (!all) hideNotices();
            beforeSendWaiting();
          },
          complete: function(jqXHR, textStatus) {
            completeWaiting();
          },
          success: function(data, textStatus, jqXHR) {
            (data && data.error) ? errorCallback(data.error) : successCallback();
          },
          error: function(jqXHR, textStatus, error) {
            errorCallback(textStatus);
          }
        }));
      });
    }

    // Check Credentials Without Before / Complete Callbacks ----- TRANSLATE IN ERROR CALL ISN'T SET
    function checkCredentials() {
      if (!_allFieldsFilled()) return;
      _ajaxCall(true);
    }

    // Check Credentials: Observe User Events with Delay
    var _observe = function() {
      var timeout_id;

      // Anonymous function handle setTimeout()
      var checkCredentialsWithDelay = function() {
        if (timeout_id) clearTimeout(timeout_id);
        timeout_id = setTimeout(function() { _ajaxCall(false); }, 750);
      }

      $("#" + config.name + "_container input").on('keyup', function(e) {
        clearCallback();
        checkCredentialsWithDelay();
      });

      // Sync
      $('.' + config.name + '-api-sync').on('click', function(e) {
        if (confirm(I18n.t('customers.form.devices.sync.confirm'))) {
          $.ajax({
            url: '/api/0.1/devices/' + config.name + '/sync.json',
            type: 'POST',
            data: $.extend(_userCredential(), {
              customer_id: params.customer_id
            }),
            beforeSend: function(jqXHR, settings) {
              beforeSendWaiting();
            },
            complete: function(jqXHR, textStatus) {
              completeWaiting();
            },
            success: function(data, textStatus, jqXHR) {
              alert(I18n.t('customers.form.devices.sync.complete'));
            }
          });
        }
      });
    }

    /* Password Inputs: set fake password  (input view fake) */
    if ("password" in config) {
      var password_field = '#' + [base_name, config.name, "password"].join('_');
      if ($(password_field).val() == '') {
        $(password_field).val(params.default_password);
      }
    };

    // Check credantial for current device config
    // Observe Widget if Customer has Service Enabled or Admin (New Customer)
    checkCredentials();
    _observe();
  }

  /* Chrome / FF, Prevent Sending Default Password
     The browsers would ask to remember it. */
  (function() {
    $('form.clear-passwords').on('submit', function(e) {
      $.each($(e.target).find('input[type=\'password\']'), function(i, element) {
        if ($(element).val() == params.default_password) {
          $(element).val('');
        }
      });
      return true;
    });
  })();

  var initialize = function(params) {
    $.each(params['devices'], function(deviceName, config) {
      config.name = deviceName;
      _devicesInitCustomer('customer_devices', config, params);
    });
  }

  return { init: initialize };
})();

Paloma.controller('Customers', {
  index: function() {
    customers_index(this.params);
  },
  new: function() {
    customers_edit(this.params);
  },
  create: function() {
    customers_edit(this.params);
  },
  edit: function() {
    customers_edit(this.params);
  },
  update: function() {
    customers_edit(this.params);
  }
});
