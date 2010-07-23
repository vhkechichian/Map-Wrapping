class LayersController < ApplicationController


  layout 'layerdetail', :only => [:show,  :edit, :export, :metadata]
  before_filter :login_required , :except => [:wms, :wms2, :show_kml, :show, :index, :metadata, :maps, :thumb, :geosearch]
  before_filter :check_administrator_role, :only => [:publish, :toggle_visibility, :merge, :remove_map, :update_year, :update, :destroy, :create]
  before_filter :find_layer, :only => [:show, :export, :metadata, :digitize, :toggle_visibility, :update_year, :publish, :remove_map, :merge, :maps, :thumb]


  helper :sort
  include SortHelper

  #method get's the thumb url for the first map in the layer

  def thumb
    redirect_to @layer.thumb
  end


  require 'yahoo-geoplanet'
  def geosearch
    sort_init 'updated_at'
    sort_update

    extents = [-74.1710,40.5883,-73.4809,40.8485] #NYC

    #TODO change to straight javascript call.
    if params[:place] && !params[:place].blank?
      place_query = params[:place]
      Yahoo::GeoPlanet.app_id = Yahoo_app_id
      geoplanet_result = Yahoo::GeoPlanet::Place.search(place_query, :count => 2)
      if geoplanet_result[0]
        g_bbox =  geoplanet_result[0].bounding_box.map!{|x| x.reverse}
        extents = g_bbox[1] + g_bbox[0]
        render :json => extents.to_json
        return
      else
        render :json => extents.to_json
        return
      end
    end

  if params[:bbox] && params[:bbox].split(',').size == 4
    begin
      extents = params[:bbox].split(',').collect {|i| Float(i)}
    rescue ArgumentError
      logger.debug "arg error with bbox, setting extent to defaults"
    end
  end
  @bbox = extents.join(',')
  if extents
    bbox_poly_ary = [
      [ extents[0], extents[1] ],
      [ extents[2], extents[1] ],
      [ extents[2], extents[3] ],
      [ extents[0], extents[3] ],
      [ extents[0], extents[1] ]
    ]

    bbox_polygon = Polygon.from_coordinates([bbox_poly_ary]).as_ewkt
    if params[:operation] == "within"
      conditions = ["ST_Within(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))"]
    else
      conditions = ["ST_Intersects(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))"]
    end

  else
    conditions = nil
  end


  if params[:sort_order] && params[:sort_order] == "desc"
    sort_nulls = " NULLS LAST"
  else
    sort_nulls = " NULLS FIRST"
  end
  @operation = params[:operation]

  if @operation == "intersect"
    sort_geo = "ABS(ST_Area(bbox_geom) - ST_Area(ST_GeomFromText('#{bbox_polygon}'))) ASC,  "
  else
    sort_geo ="ST_Area(bbox_geom) DESC ,"
  end

  paginate_params = {
    :select => "bbox, name, updated_at, id, maps_count, rectified_maps_count, depicts_year",
    :page => params[:page],
    :per_page => 20,
    :order => sort_geo + sort_clause + sort_nulls,
    :conditions => conditions
  }
  @layers = Layer.visible.with_maps.paginate(paginate_params)
  @jsonlayers = @layers.to_json
  respond_to do |format|
    format.html{ render :layout =>'application' }
    format.json { render :json => {:stat => "ok",
      :current_page => @layers.current_page,
      :per_page => @layers.per_page,
      :total_entries => @layers.total_entries,
      :total_pages => @layers.total_pages,
      :items => @layers.to_a}.to_json , :callback => params[:callback]}
  end
end



  def index
    sort_init 'created_at'
    session[@sort_name] = nil  #remove the session sort as we have percent
    sort_update
    @query = params[:query]
    @field = %w(name description).detect{|f| f== (params[:field])}
    @field = "name" if @field.nil?
    if @query && @query != "null" #null will be set by pagless js if theres no query
      conditions =   ["#{@field}  ~* ?", '(:punct:|^|)'+@query+'([^A-z]|$)']
    else
      conditions = nil
    end
    if params[:sort_key] == "percent"
      select = "*, round(rectified_maps_count::float / maps_count::float * 100) as percent"
      conditions.nil? ? conditions = ["maps_count > 0"] : conditions.add_condition('maps_count > 0')
    else
      select = nil
    end

    if params[:sort_order] && params[:sort_order] == "desc"
      sort_nulls = " NULLS LAST"
    else
      sort_nulls = " NULLS FIRST"
    end

    paginate_params = {
      :page => params[:page],
      :per_page => 20,
      :select => select,
      :order => sort_clause + sort_nulls,
      :conditions => conditions
    }

    map = params[:map_id]
    if !map.nil?
      @map = Map.find(map)
      @layers = @map.layers.paginate(paginate_params)
      @html_title = "Layer List for Map #{@map.id}"
      @page = "for_map"
    else
      @layers = Layer.paginate(paginate_params)
      @html_title = "Browse Layer List"
    end
    
    if request.xhr?
      # for pageless :
      # #render :partial => 'layer', :collection => @layers
      render :action => 'index.rjs'
    else
      respond_to do |format|
        format.html {render :layout => "application"}
        format.json {render :json => {:layers => @map.layers.visible.to_json}}  #only to be called if theres a maps in the url
      end
    end
  end

  #method returns json object of a layers warped maps
  def maps
    @maps = @layer.maps.warped
    respond_to do |format|
      format.json {render :json => {:maps => @maps.to_json(:only => [:id, :bbox, :title, :width, :height])}}
    end
  end

  def show
    @current_tab = "show"
    @selected_tab = 0
    @disabled_tabs =  []
    unless @layer.rectified_maps_count > 0 #i.e. if the layer has no maps, then dont let people digitizer or export
      @disabled_tabs = ["digitize","export"]
    end

    if  logged_in? && (@layer.user  = current_user or current_user.has_role?("editor"))
      @maps = @layer.maps.paginate(:page => params[:page], :per_page => 30, :order => :map_type)
    else
      @disabled_tabs += ["edit"]
      @maps = @layer.maps.public.paginate(:page => params[:page], :per_page => 30, :order => :map_type)
    end
    @html_title = "Viewing Layer "+ @layer.id.to_s

    if request.xhr?
      unless params[:page]
        @xhr_flag = "xhr"
        render :action => "show", :layout => "layer_tab_container"
      else
        render :action =>  "show_maps.rjs"
      end
    else
      respond_to do |format|
        format.html {render :layout => "layerdetail"}# show.html.erb
        format.json {render :json => {:layer => @layer, :maps => @layer.maps.warped}.to_json }
        format.kml {render :action => "show_kml", :layout => false}
      end
    end
  end


  def new
    #assume that the user is logged in
    @html_title = "Make new layer -"
    @layer = Layer.new
    @maps = current_user.maps
    respond_to do |format|
        format.html {render :layout => "application"}# show.html.erb
    end
  end

  def create
    @layer = Layer.new params[:layer]
    #@maps = current_user.maps.warped
    @layer.user = current_user

    #@layer.maps = Map.find(params[:map_ids]) if params[:map_ids]
    if params[:map_ids]
      selected_maps = Map.find(params[:map_ids])
      selected_maps.each {|map| @layer.maps << map}
    end

    if @layer.save
      @layer.update_layer
      @layer.update_counts
      flash[:notice] = "Layer was successfully created."
      redirect_to layer_url(@layer)
    else
      redirect_to new_layer_url
    end
  end

  def edit
    @layer = Layer.find(params[:id])
    @selected_tab = 1
    @current_tab = "edit"
    @html_title = "Editing Layer #{@layer.id} on"
    if (!current_user.own_this_layer?(params[:id]) and current_user.has_role?("editor"))
      @maps = @layer.user.maps
    else
      @maps = current_user.maps  #current_user.maps.warped
    end

    if request.xhr?
      @xhr_flag = "xhr"
      render :action => "edit", :layout => "layer_tab_container"
    else
      respond_to do |format|
        format.html {render :layout => "layerdetail"}# show.html.erb
      end
    end
  end

  def update
    @layer = Layer.find(params[:id])
    @maps = current_user.maps
    @layer.maps = Map.find(params[:map_ids]) if params[:map_ids]
    if @layer.update_attributes(params[:layer])
      @layer.update_layer
      @layer.update_counts
      flash.now[:notice] = "Layer was successfully updated."
      #redirect_to layer_url(@layer)
    else

    end
    if request.xhr?
      @xhr_flag = "xhr"
      render :action => "edit", :layout => "layer_tab_container"
    else
      respond_to do |format|
        format.html { render :action => "edit",:layout => "layerdetail" }
      end
    end
  end

  def delete
    @layer = Layer.find(params[:id])
    respond_to do |format|
        format.html {render :layout => "application"}
    end
  end
  
  def destroy
    if logged_in? and (current_user.own_this_layer?(params[:id])  or current_user.has_role?("editor"))
      @layer = Layer.find(params[:id])
    else
      flash[:notice] = "Sorry, you cannot delete other people's layers!"
      redirect_to layers_path
    end

    if @layer.destroy
      flash[:notice] = "Layer deleted!"
    else
      flash[:notice] = "Layer wasnt deleted"
    end
    respond_to do |format|
      format.html { redirect_to(layers_url) }
      format.xml  { head :ok }
    end
  end

  def export
    @current_tab = "export"
    @selected_tab = 3

    if request.xhr?
      @xhr_flag = "xhr"
      render :layout => "layer_tab_container"
    else
      respond_to do |format|
        format.html {render :layout => "layerdetail"}
      end
    end
  end

  def metadata
    @current_tab = "metadata"
    @selected_tab = 4
    #@layer_properties = @layer.layer_properties
    choose_layout_if_ajax
  end

  def digitize
    @current_tab = "digitize"
    @selected_tab = 2
    @html_title = "Digitizing Layer "+ @layer.id.to_s

    if request.xhr?
      @xhr_flag = "xhr"
      render :action => "digitize", :layout => "tab_container"
    else
      if @layer.rectified_maps_count > 0
        respond_to do |format|
          format.html {render :layout => "layerdetail"}
        end
      else
        redirect_to :action => 'show'
      end
    end

  end

  #merge this layer with another one
  #moves all child object to new parent
  def merge
    if request.get?
      #just show form
      render :layout => 'application'
    elsif request.put?
      @dest_layer = Layer.find(params[:dest_id])
      #TODO uncomment following line to enable this
      #@layer.merge(@dest_layer.id)
      render :text  => "Layer has been merged into new layer - all maps copied across! (functionality disabled at the moment)"
    end
  end

  def remove_map
    @map = Map.find(params[:map_id])
    if request.get?
      #shows the form
      render :layout => 'application'
    elsif request.put?
      #TODO uncomment following line to enable this
      #@layer.remove_map(@map.id)
      render :text =>  "Map has been removed from this layer (functionality disabled at the moment) "
    end
  end

  def toggle_visibility
    @layer.is_visible = !@layer.is_visible
    @layer.save
    @layer.update_layer
    if @layer.is_visible
      update_text = "(Visible)"
    else
      update_text = "(Not Visible)"
    end
    render :text => update_text
  end

  def update_year
    @layer.update_attributes(params[:layer])
    render :text => "Depicts : " + @layer.depicts_year.to_s
  end

  def publish
    if @layer.rectified_percent < 100
      render :text => "Layer has less than 100% of its maps rectified"
      #redirect_to :action => 'index'
    else
      @layer.publish
      render :text => "Layer will be published (this functionality is disabled at the moment)"
    end
  end

  require 'mapscript'
  include Mapscript
  def wms()

    @layer = Layer.find(params[:id])
    ows = Mapscript::OWSRequest.new

    ok_params = Hash.new
    # params.each {|k,v| k.upcase! } frozen string error

    params.each {|k,v| ok_params[k.upcase] = v }

    [:request, :version, :transparency, :service, :srs, :width, :height, :bbox, :format, :srs].each do |key|

      ows.setParameter(key.to_s, ok_params[key.to_s.upcase]) unless ok_params[key.to_s.upcase].nil?
    end

    ows.setParameter("STYLES", "")
    ows.setParameter("LAYERS", "image")
    #ows.setParameter("COVERAGE", "image")

    map = Mapscript::MapObj.new(File.join(RAILS_ROOT, '/db/maptemplates/wms.map'))
    projfile = File.join(RAILS_ROOT, '/lib/proj')
    map.setConfigOption("PROJ_LIB", projfile)
    #map.setProjection("init=epsg:900913")
    map.applyConfigOptions

    # logger.info map.getProjection
    map.setMetaData("wms_onlineresource",
      "http://" + request.host_with_port + "/layers/wms/#{@layer.id}")

    raster = Mapscript::LayerObj.new(map)
    raster.name = "image"
    raster.type =  Mapscript::MS_LAYER_RASTER
    raster.tileindex = @layer.tileindex_path
    raster.tileitem = "Location"

    raster.status = Mapscript::MS_ON
    #raster.setProjection( "+init=" + str(epsg).lower() )
    raster.dump = Mapscript::MS_TRUE

    #raster.setProjection('init=epsg:4326')
    raster.metadata.set('wcs_formats', 'GEOTIFF')
    raster.metadata.set('wms_title', @layer.name)
    raster.metadata.set('wms_srs', 'EPSG:4326 EPSG:4269 EPSG:900913')
    raster.debug = Mapscript::MS_TRUE

    Mapscript::msIO_installStdoutToBuffer
    result = map.OWSDispatch(ows)
    content_type = Mapscript::msIO_stripStdoutBufferContentType || "text/plain"
    result_data = Mapscript::msIO_getStdoutBufferBytes

    send_data result_data, :type => content_type, :disposition => "inline"
    Mapscript::msIO_resetHandlers
  end


  #TODO merge wms and wm2 into one...or use tilecache for serving layers
  #this action lists all visible layers that have maps in them, and thus should
  #have a tileindex and something to view.
  def wms2

    @layer_name = params[:LAYERS]

    ows = Mapscript::OWSRequest.new

    ok_params = Hash.new
    # params.each {|k,v| k.upcase! } frozen string error

    params.each {|k,v| ok_params[k.upcase] = v }

    [:request, :version, :transparency, :service, :srs, :width, :height, :bbox, :format, :srs, :layers].each do |key|

      ows.setParameter(key.to_s, ok_params[key.to_s.upcase]) unless ok_params[key.to_s.upcase].nil?
    end

    ows.setParameter("STYLES", "")
    #ows.setParameter("LAYERS", "image")

    map = Mapscript::MapObj.new(File.join(RAILS_ROOT, '/db/maptemplates/wms.map'))
    projfile = File.join(RAILS_ROOT, '/lib/proj')
    map.setConfigOption("PROJ_LIB", projfile)
    #map.setProjection("init=epsg:900913")
    map.applyConfigOptions

    # logger.info map.getProjection
    map.setMetaData("wms_onlineresource",
      "http://" + request.host_with_port  + "/layers/wms2")
    unless @layer_name

      Layer.visible.each do |layer|
        if layer.rectified_maps_count > 0
          raster = Mapscript::LayerObj.new(map)
          #raster.name = "layer_"+layer.id.to_s
          raster.name = "layer_"+layer.id.to_s
          raster.type =  Mapscript::MS_LAYER_RASTER
          raster.tileindex = layer.tileindex_path
          raster.tileitem = "Location"

          raster.status = Mapscript::MS_ON
          raster.dump = Mapscript::MS_TRUE

          raster.metadata.set('wcs_formats', 'GEOTIFF')
          # raster.metadata.set('wms_title', "layer "+layer.id.to_s)
          raster.metadata.set('wms_title', layer.id.to_s + ": "+snippet(layer.name, 15))

          raster.metadata.set('wms_abstract', layer.rectified_maps_count.to_s + "maps. "+
              layer.rectified_percent.to_i.to_s + "% Complete"+
              "[Depicts:"+layer.depicts_year.to_s+"]")

          raster.metadata.set('wms_keywordlist', 'depictsYear:'+layer.depicts_year.to_s +
              ',totalMaps:' + layer.maps.count.to_s +
              ',numberWarpedMaps:'+ layer.rectified_maps_count.to_s +
              ',percentComplete:'+ layer.rectified_percent.to_i.to_s +
              ',lastUpdated:' + layer.updated_at.to_s )
          raster.metadata.set('wms_srs', 'EPSG:4326 EPSG:4269 EPSG:900913')
          raster.debug = Mapscript::MS_TRUE
        end
      end

    else
      single_layer = Layer.find(@layer_name.to_s.delete("layer_"))
      raster = Mapscript::LayerObj.new(map)
      raster.name = "layer_"+single_layer.id.to_s
      raster.type =  Mapscript::MS_LAYER_RASTER
      raster.tileindex = single_layer.tileindex_path
      raster.tileitem = "Location"

      raster.status = Mapscript::MS_ON
      raster.dump = Mapscript::MS_TRUE

      raster.metadata.set('wcs_formats', 'GEOTIFF')
      raster.metadata.set('wms_title', single_layer.name)
      raster.metadata.set('wms_srs', 'EPSG:4326 EPSG:4269 EPSG:900913')
      raster.metadata.set('wms_keywordlist', 'depictsYear:'+layer.depicts_year.to_s +
          ',totalMaps:' + layer.maps.count.to_s +
          ',warpedMaps:'+ layer.rectified_maps_count.to_s +
          ',percentComplete:'+ layer.rectified_percent.to_i.to_s +
          ',lastUpdated:' + layer.updated_at.to_s )

      raster.debug = Mapscript::MS_TRUE
    end

    Mapscript::msIO_installStdoutToBuffer
    result = map.OWSDispatch(ows)
    content_type = Mapscript::msIO_stripStdoutBufferContentType || "text/plain"
    result_data = Mapscript::msIO_getStdoutBufferBytes

    send_data result_data, :type => content_type, :disposition => "inline"
    Mapscript::msIO_resetHandlers
  end

  private

  #little helper method
  def snippet(thought, wordcount)
    thought.split[0..(wordcount-1)].join(" ") +(thought.split.size > wordcount ? "..." : "")
  end

  def find_layer
    @layer = Layer.find(params[:id])
  end

  def choose_layout_if_ajax
    if request.xhr?
      @xhr_flag = "xhr"
      render :layout => "layer_tab_container"
    end
  end
  
end
