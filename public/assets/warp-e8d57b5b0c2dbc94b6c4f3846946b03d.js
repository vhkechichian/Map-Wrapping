function init(){from_map=new OpenLayers.Map("from_map",{controls:[new OpenLayers.Control.PanZoomBar],maxExtent:new OpenLayers.Bounds(0,0,image_width,image_height),maxResolution:"auto",numZoomLevels:20});var e=new OpenLayers.Layer.WMS(title,wms_url,{format:"image/png",status:"unwarped"},{transitionEffect:"resize"});from_map.addLayer(e),from_map.getCenter()||from_map.zoomToMaxExtent(),OpenLayers.IMAGE_RELOAD_ATTEMPTS=3,OpenLayers.Util.onImageLoadErrorColor="transparent",to_layer_switcher=new OpenLayers.Control.LayerSwitcher;var t={projection:new OpenLayers.Projection("EPSG:900913"),displayProjection:new OpenLayers.Projection("EPSG:4326"),units:"m",numZoomLevels:20,maxResolution:156543.0339,maxExtent:new OpenLayers.Bounds(-20037508,-20037508,20037508,20037508.34),controls:[new OpenLayers.Control.Attribution,to_layer_switcher,new OpenLayers.Control.PanZoomBar]};to_map=new OpenLayers.Map("to_map",t),warped_layer=new OpenLayers.Layer.WMS.Untiled("warped map",wms_url,{format:"image/png",status:"warped"},{TRANSPARENT:"true",reproject:"true"},{gutter:15,buffer:0},{projection:"epsg:4326",units:"m"});var r=.6;warped_layer.setOpacity(r),warped_layer.setVisibility(!1),warped_layer.setIsBaseLayer(!1),to_map.addLayer(warped_layer),to_map.addLayer(mapnik);for(var a=0;a<layers_array.length;a++)to_map.addLayer(get_map_layer(layers_array[a]));jpl_wms.setVisibility(!1),to_map.addLayer(jpl_wms),map_has_bounds?(map_bounds_merc=new OpenLayers.Bounds,map_bounds_merc=lonLatToMercatorBounds(map_bounds),to_map.zoomToExtent(map_bounds_merc)):to_map.setCenter(lonLatToMercator(new OpenLayers.LonLat(0,0)),10);var o=OpenLayers.Util.extend({},OpenLayers.Feature.Vector.style["default"]);o.graphicOpacity=1,o.graphicWidth=14,o.graphicHeight=22,o.graphicXOffset=-(o.graphicWidth/2),o.graphicYOffset=-o.graphicHeight,o.externalGraphic=icon_imgPath+"AQUA.png",to_vectors=new OpenLayers.Layer.Vector("To vector markers"),to_vectors.displayInLayerSwitcher=!1,from_vectors=new OpenLayers.Layer.Vector("From vector markers"),from_vectors.displayInLayerSwitcher=!1,active_to_vectors=new OpenLayers.Layer.Vector("active To vector markers",{style:o}),active_to_vectors.displayInLayerSwitcher=!1,active_from_vectors=new OpenLayers.Layer.Vector("active from vector markers",{style:o}),active_from_vectors.displayInLayerSwitcher=!1,to_map.addLayers([to_vectors,active_to_vectors]),from_map.addLayers([from_vectors,active_from_vectors]);var n=new OpenLayers.Control.Panel({displayClass:"olControlEditingToolbar"}),i=new OpenLayers.Control.DragFeature(to_vectors,{displayClass:"olControlDragFeature",title:"Move Control Point"});i.onComplete=function(e){saveDraggedMarker(e)};var s=new OpenLayers.Control.DrawFeature(active_to_vectors,OpenLayers.Handler.Point,{displayClass:"olControlDrawFeaturePoint",title:"Add Control Point",handlerOptions:{style:o}});s.featureAdded=function(e){newaddGCPto(e)};var l=new OpenLayers.Control.DrawFeature(active_from_vectors,OpenLayers.Handler.Point,{displayClass:"olControlDrawFeaturePoint",title:"Add Control Point",handlerOptions:{style:o}});l.featureAdded=function(e){newaddGCPfrom(e)};var m=new OpenLayers.Control.Panel({displayClass:"olControlEditingToolbar"}),p=new OpenLayers.Control.DragFeature(from_vectors,{displayClass:"olControlDragFeature",title:"Move Control Point"});p.onComplete=function(e){saveDraggedMarker(e)},navig=new OpenLayers.Control.Navigation({title:"Move Around Map"}),navigFrom=new OpenLayers.Control.Navigation({title:"Move Around Map"}),n.addControls([navig,i,s]),to_map.addControl(n),m.addControls([navigFrom,p,l]),from_map.addControl(m),to_map.addControl(new OpenLayers.Control.Navigation),from_map.addControl(new OpenLayers.Control.Navigation),navig.activate(),navigFrom.activate(),joinControls(i,p),joinControls(navig,navigFrom),joinControls(s,l),jQuery("#warped-slider").slider({value:100*r,range:"min",slide:function(e,t){warped_layer.setOpacity(t.value/100)}}),jQuery("#warped-slider").hide(),warped_layer.events.register("visibilitychanged",this,function(e){e.object.getVisibility()===!0?jQuery("#warped-slider").show():jQuery("#warped-slider").hide()})}function joinControls(e,t){e.events.register("activate",e,function(){t.activate()}),e.events.register("deactivate",e,function(){t.deactivate()}),t.events.register("activate",t,function(){e.activate()}),t.events.register("deactivate",t,function(){e.deactivate()})}function get_map_layer(e){var t=layer_baseurl+"/"+e,r=new OpenLayers.Layer.WMS("Layer "+e,t,{format:"image/png"},{TRANSPARENT:"true",reproject:"true"},{gutter:15,buffer:0},{projection:"epsg:4326",units:"m"});return r.setIsBaseLayer(!1),r.visibility=!1,r}function moveStart(){var e,t;1==this?(t=from_map,e=to_map):(t=to_map,e=from_map);var r=t.getCenter();origXYZ.lonlat=r,origXYZ.zoom=t.zoom}function moveEnd(){if(!moving){moving=!0;var e,t;1==this?(t=from_map,e=to_map):(t=to_map,e=from_map);var r=e.zoom;origXYZ.zoom!=t.zoom&&(diffzoom=origXYZ.zoom-t.zoom,r=e.zoom-diffzoom);var a=t.getPixelFromLonLat(origXYZ.lonlat),o=t.getPixelFromLonLat(t.getCenter()),n=a.x-o.x,i=a.y-o.y,s=e.getPixelFromLonLat(e.getCenter());e.setCenter(e.getLonLatFromPixel(new OpenLayers.Pixel(s.x-n,s.y-i)),r,!1,!1),moving=!1}}function toggleJoinLinks(){mapLinked===!0?(mapLinked=!1,document.getElementById("link-map-button").className="link-map-button-off"):(mapLinked=!0,document.getElementById("link-map-button").className="link-map-button-on"),mapLinked===!0?(from_map.events.register("moveend",1,moveEnd),to_map.events.register("moveend",0,moveEnd),from_map.events.register("movestart",1,moveStart),to_map.events.register("movestart",0,moveStart)):(from_map.events.unregister("moveend",1,moveEnd),to_map.events.unregister("moveend",0,moveEnd),from_map.events.unregister("movestart",1,moveStart),to_map.events.unregister("movestart",0,moveStart))}function gcp_notice(e){jqHighlight("rectifyNotice"),notice=document.getElementById("gcp_notice"),notice.innerHTML=e}function update_gcp_field(e,t){var r=e,a=t.value,o=t.id.substring(0,t.id.length-(r+"").length),n=gcp_update_field_url+"/"+r;jQuery("#spinner").show(),gcp_notice("Updating...");jQuery.ajax({type:"PUT",url:n,data:{authenticity_token:encodeURIComponent(window._token),attribute:o,value:a}}).success(function(){gcp_notice("Control Point updated!"),move_map_markers(e,t)}).done(function(){jQuery("#spinner").hide()}).fail(function(){gcp_notice("Had trouble updating that point with the server. Try again?"),t.value=a})}function update_gcp(t,r){var a=t,o=gcp_update_url+"/"+a;for(i=0;i<r.childNodes.length;i++)for(listtd=r.childNodes[i],e=0;e<listtd.childNodes.length;e++)listItem=listtd.childNodes[e],listItem.id=="x"+t&&(x=listItem.value),listItem.id=="y"+t&&(y=listItem.value),listItem.id=="lon"+t&&(lon=listItem.value),listItem.id=="lat"+t&&(lat=listItem.value);gcp_notice("Updating..."),jQuery("#spinner").show();jQuery.ajax({type:"PUT",url:o,data:{authenticity_token:encodeURIComponent(window._token),x:x,y:y,lon:lon,lat:lat}}).success(function(){gcp_notice("Control Point updated!")}).done(function(){jQuery("#spinner").hide()}).fail(function(){gcp_notice("Had trouble updating that point with the server. Try again?"),elem.value=value})}function move_map_markers(t,r){var a=r.value,o=r.id;for(trele=r.parentNode.parentNode,i=0;i<trele.childNodes.length;i++)for(trchild=trele.childNodes[i],e=0;e<trchild.childNodes.length;e++)inp=trchild.childNodes[e],inp.id=="x"+t&&(x=inp.value),inp.id=="y"+t&&(y=image_height-inp.value),inp.id=="lon"+t&&(tlon=inp.value),inp.id=="lat"+t&&(tlat=inp.value);if(o=="x"+t||o=="y"+t){for(var n,s=0;s<from_vectors.features.length;s++)from_vectors.features[s].gcp_id==t&&(n=from_vectors.features[s]);o=="x"+t&&(x=a),o=="y"+t&&(y=image_height-a),n.geometry.x=x,n.geometry.y=y,n.geometry.clearBounds(),n.layer.drawFeature(n)}else if(o=="lon"+t||o=="lat"+t){for(var l,m=0;m<to_vectors.features.length;m++)to_vectors.features[m].gcp_id==t&&(l=to_vectors.features[m]);o=="lon"+t&&(tlon=a),o=="lat"+t&&(tlat=a),hacklonlat=lonLatToMercator(new OpenLayers.LonLat(tlon,tlat)),l.geometry.x=hacklonlat.lon,l.geometry.y=hacklonlat.lat,l.geometry.clearBounds(),l.layer.drawFeature(l)}}function saveDraggedMarker(t){var r=document.getElementById("gcp"+t.gcp_id);for(i=0;i<r.childNodes.length;i++)for(listtd=r.childNodes[i],e=0;e<listtd.childNodes.length;e++)if(listItem=listtd.childNodes[e],t.layer==from_vectors&&(listItem.id=="x"+t.gcp_id&&(listItem.value=t.geometry.x),listItem.id=="y"+t.gcp_id&&(listItem.value=image_height-t.geometry.y)),t.layer==to_vectors){var a=new OpenLayers.LonLat(t.geometry.x,t.geometry.y),o=mercatorToLonLat(a);listItem.id=="lon"+t.gcp_id&&(listItem.value=o.lon),listItem.id=="lat"+t.gcp_id&&(listItem.value=o.lat)}update_gcp(t.gcp_id,r)}function save_new_gcp(e,t,r,a){url=gcp_add_url,gcp_notice("Adding..."),jQuery("#spinner").show();jQuery.ajax({type:"POST",url:url,data:{authenticity_token:encodeURIComponent(window._token),x:e,y:t,lat:a,lon:r}}).done(function(){update_row_numbers(),jQuery("#spinner").hide()}).fail(function(){gcp_notice("Had trouble saving that point to the server. Try again?")})}function update_rms(e){fi=document.getElementById("errortitle"),fi.value="Error("+e+")"}function delete_markers(e){for(var t=0;t<from_vectors.features.length;t++)from_vectors.features[t].gcp_id==e&&(del_from_mark=from_vectors.features[t],del_to_mark=to_vectors.features[t],from_vectors.destroyFeatures([del_from_mark]),to_vectors.destroyFeatures([del_to_mark]));update_row_numbers()}function update_row_numbers(){for(var e=0;e<from_vectors.features.length;e++){temp_marker=from_vectors.features[e],li_ele=document.getElementById("gcp"+temp_marker.gcp_id),inputs=li_ele.getElementsByTagName("input");for(var t=0;t<inputs.length;t++)inputs[t].name=="error"+temp_marker.gcp_id&&(error=inputs[t].value);var r=getColorString(error);if(updateGcpColor(from_vectors.features[e],r),updateGcpColor(to_vectors.features[e],r),span_ele=li_ele.getElementsByTagName("span"),"marker_number"==span_ele[0].className){var a="<img src='"+icon_imgPath+(temp_marker.id_index+1)+r+".png' />";span_ele[0].innerHTML=a}}redrawGcpLayers()}function redrawGcpLayers(){from_vectors.redraw(),to_vectors.redraw()}function updateGcpColor(e,t){e.style.externalGraphic=icon_imgPath+(e.id_index+1)+t+".png"}function getColorString(e){var t="";return 5>e?t="":e>=5&&10>e?t="_green":e>=10&&50>e?t="_orange":e>=50&&(t="_red"),t}function populate_gcps(e,t,r,a,o,n){n="undefined"!=typeof n?n:0;var i=getColorString(n);index=gcp_markers.length,gcp_markers.push(index),got_lon=t,got_lat=image_height-r,add_gcp_marker(from_vectors,new OpenLayers.LonLat(got_lon,got_lat),!1,index,e,i),add_gcp_marker(to_vectors,lonLatToMercator(new OpenLayers.LonLat(a,o)),!1,index,e,i)}function set_gcp(){if(check_if_gcp_ready(),!temp_gcp_status)return alert("You have to add a new control point on each map before pressing this button."),!1;var e=from_templl,t=mercatorToLonLat(to_templl),r=e.lon,a=e.lat,o=image_height-a,n=r;save_new_gcp(n,o,t.lon,t.lat),active_from_vectors.destroyFeatures(),active_to_vectors.destroyFeatures()}function add_gcp_marker(e,t,r,a,o,n){n="undefined"!=typeof n?n:"",a="undefined"!=typeof a?a:-2;var i=OpenLayers.Util.extend({},OpenLayers.Feature.Vector.style["default"]);i.graphicOpacity=1,i.graphicWidth=14,i.graphicHeight=22,i.graphicXOffset=-(i.graphicWidth/2),i.graphicYOffset=-i.graphicHeight,r===!0?active_style.externalGraphic=icon_imgPath+"AQUA.png":i.externalGraphic=icon_imgPath+(a+1)+n+".png";var s=new OpenLayers.Geometry.Point(t.lon,t.lat),l=new OpenLayers.Feature.Vector(s,null,i);l.id_index=a,l.gcp_id=o,e.addFeatures([l]),resetHighlighting()}function addLayerToDest(e){num=e.layer_num.value,new_wms_url=empty_wms_url+"/"+num,new_warped_layer=new OpenLayers.Layer.WMS.Untiled("warped map "+num,new_wms_url,{format:"image/png",status:"warped"},{TRANSPARENT:"true",reproject:"true"},{gutter:15,buffer:0},{projection:"epsg:4326",units:"m"}),new_warped_layer.setOpacity(.6),new_warped_layer.setVisibility(!0),new_warped_layer.setIsBaseLayer(!1),to_map.addLayer(new_warped_layer),to_layer_switcher.maximizeControl(),jQuery("#add_layer").hide()}function show_warped_map(){warped_layer.setVisibility(!0),warped_layer.mergeNewParams({random:Math.random()}),warped_layer.redraw(!0),to_layer_switcher.maximizeControl(),"undefined"!=typeof warpedmap&&"undefined"!=typeof warped_wmslayer&&(warped_wmslayer.mergeNewParams({random:Math.random()}),warped_wmslayer.redraw(!0))}function check_if_gcp_ready(){active_to_vectors.features.length>0&&active_from_vectors.features.length>0?(temp_gcp_status=!0,document.getElementById("addPointDiv").className="addPointHighlighted",document.getElementById("GcpButton").disabled=!1):temp_gcp_status=!1}function newaddGCPto(e){if(active_to_vectors.features.length>1){for(var t=new Array,r=0;r<active_to_vectors.features.length;r++)active_to_vectors.features[r]!=e&&t.push(active_to_vectors.features[r]);active_to_vectors.destroyFeatures(t)}var a=new OpenLayers.LonLat(e.geometry.x,e.geometry.y);highlight(to_map.div),to_templl=a,check_if_gcp_ready()}function newaddGCPfrom(e){if(active_from_vectors.features.length>1){for(var t=new Array,r=0;r<active_from_vectors.features.length;r++)active_from_vectors.features[r]!=e&&t.push(active_from_vectors.features[r]);active_from_vectors.destroyFeatures(t)}var a=new OpenLayers.LonLat(e.geometry.x,e.geometry.y);highlight(from_map.div),from_templl=a,check_if_gcp_ready()}function addLayerToDest(e){num=e.layer_num.value,new_wms_url=empty_wms_url+"/"+num,new_warped_layer=new OpenLayers.Layer.WMS.Untiled("warped map "+num,new_wms_url,{format:"image/png",status:"warped"},{TRANSPARENT:"true",reproject:"true"},{gutter:15,buffer:0},{projection:"epsg:4326",units:"m"}),new_warped_layer.setOpacity(.6),new_warped_layer.setVisibility(!0),new_warped_layer.setIsBaseLayer(!1),to_map.addLayer(new_warped_layer),to_layer_switcher.maximizeControl(),jQuery("#add_layer").hide()}function resetHighlighting(){to_map.div.className="map-off",from_map.div.className="map-off",document.getElementById("addPointDiv").className="addPoint",document.getElementById("GcpButton").disabled=!0}function highlight(e){e.className="highlighted"}function mercatorToLonLat(e){var t=e.lon/20037508.34*180,r=e.lat/20037508.34*180;return r=180/Math.PI*(2*Math.atan(Math.exp(r*Math.PI/180))-Math.PI/2),new OpenLayers.LonLat(t,r)}function lonLatToMercator(e){var t=20037508.34*e.lon/180,r=Math.log(Math.tan((90+e.lat)*Math.PI/360))/(Math.PI/180);return r=20037508.34*r/180,new OpenLayers.LonLat(t,r)}function lonLatToMercatorBounds(e){var t=new OpenLayers.Projection("EPSG:4326"),r=e.transform(t,to_map.getProjectionObject());return r}function bestGuess(e){if(jQuery("#to_map_notification").hide(),"ok"==e.status&&e.count>0){var t=e.sibling_extent;zoom=10,t&&(sibBounds=new OpenLayers.Bounds.fromString(t),zoom=to_map.getZoomForExtent(sibBounds.transform(to_map.displayProjection,to_map.projection)));var r=e.places,a="Map zoomed to best guess: <a href='#' onclick='centerToMap("+r[0].lon+","+r[0].lat+","+zoom+");return false;'>"+r[0].name+"</a><br />";if(centerToMap(r[0].lon,r[0].lat,zoom),r.length>1){a+="Other places:<br />";for(var o=1;o<r.length;o++){var n=r[o];a=a+"<a href='#' onclick='centerToMap("+n.lon+","+n.lat+","+zoom+");return false;'>"+n.name+"</a><br />"}}jQuery("#to_map_notification_inner").html(a),jQuery("#to_map_notification").show("slow")}}function centerToMap(e,t,r){var a=new OpenLayers.LonLat(e,t).transform(to_map.displayProjection,to_map.projection);to_map.setCenter(a,r)}var temp_gcp_status=!1,from_templl,to_templl,warped_layer,to_layer_switcher,navig,navigFrom,to_vectors,from_vectors,active_to_vectors,active_from_vectors,moving=!1,origXYZ=new Object,mapLinked=!1;