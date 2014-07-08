OpenLayers.ImgPath = '/assets/openlayers/img/';
var addthis_share = {templates: {
    twitter: 'Checking out {{url}} (from @mapwarper)'
  }};
var addthis_config = {
  ui_click: true
};

function jsToQueryString(obj) {
  var s = "?";
  for (var o in obj) {
    if (obj.hasOwnProperty(o)) {
      s += o + "=" + obj[o] + "&";
    }
  }
  return s.substring(0, s.length - 1);
}
function queryStringToJs(qstring) {
  if (qstring.indexOf("?") == -1) {
    return {};
  }
  var q = qstring.split("?")[1];
  var args = {};
  var vars = q.split('&');
  //    console.log(vars);
  for (var i = 0; i < vars.length; i++) {
    var kv = vars[i].split('=');
    var key = kv[0];
    var value = kv[1];
    args[key] = value;
  }
  return args;
}

function reload_with_page(per_page) {
  var path = window.location.href.split('?')[0];
  var qs_obj = queryStringToJs(window.location.search);
  qs_obj.per_page = per_page;
  qs_obj.page = 1;
  var qs_str = jsToQueryString(qs_obj);
  var url = path + qs_str;
  window.location = url;
}