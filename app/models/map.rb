require "open3"
require "error_calculator"
include ErrorCalculator
class Map < ActiveRecord::Base
  
  has_many :gcps,  :dependent => :destroy
  has_many :layers_maps,  :dependent => :destroy
  has_many :layers, :through => :layers_maps # ,:after_add, :after_remove
  has_many :my_maps, :dependent => :destroy
  has_many :users, :through => :my_maps
  belongs_to :owner, :class_name => "User"
  
  has_attached_file :upload, :styles => {:thumb => ["100x100>", :png]} ,
    :url => '/:attachment/:id/:style/:basename.:extension',
    :default_url => "/assets/missing.png"
  validates_attachment_size(:upload, :less_than => MAX_ATTACHMENT_SIZE) if defined?(MAX_ATTACHMENT_SIZE)
  #attr_protected :upload_file_name, :upload_content_type, :upload_size
  validates_attachment_content_type :upload, :content_type => ["image/jpg", "image/jpeg", "image/png", "image/gif", "image/tiff"]

  acts_as_taggable
  acts_as_commentable
  acts_as_enum :map_type, [:index, :is_map, :not_map ]
  acts_as_enum :status, [:unloaded, :loading, :available, :warping, :warped, :published]
  acts_as_enum :mask_status, [:unmasked, :masking, :masked]
  acts_as_enum :rough_state, [:step_1, :step_2, :step_3, :step_4]
  audited :allow_mass_assignment => true
  
  scope :warped,    -> { where({ :status => [Map.status(:warped), Map.status(:published)], :map_type => Map.map_type(:is_map)  }) }
  scope :published, -> { where({:status => Map.status(:published), :map_type => Map.map_type(:is_map)})}
  scope :are_public, -> { where(public: true) }
  scope :real_maps, -> { where({:map_type => Map.map_type(:is_map)})}
  
  attr_accessor :upload_url
  
  after_initialize :default_values
  before_create :download_remote_image, :if => :upload_url_provided?
  before_create :save_dimensions
  after_create :setup_image
  after_destroy :delete_images
  after_destroy :delete_map, :update_counter_cache, :update_layers
  after_save :update_counter_cache
  
  ##################
  # CALLBACKS
  ###################
  
  def default_values
    self.status  ||= :unloaded  
    self.mask_status  ||= :unmasked  
    self.map_type  ||= :is_map  
    self.rough_state ||= :step_1  
  end
  
  def upload_url_provided?
    !self.upload_url.blank?
  end
  
  def download_remote_image
    img_upload = do_download_remote_image
    unless img_upload
      errors.add(:upload_url, "is invalid or inaccessible")
      return false
    end
    self.upload = img_upload
    self.source_uri = upload_url
    
    if Map.find_by_upload_file_name(upload.original_filename)
      errors.add(:filename, "is already being used")
      return false
    end
    
  end
  
  def do_download_remote_image
    begin
      io = open(URI.parse(upload_url))
      def io.original_filename; base_uri.path.split('/').last; end
      io.original_filename.blank? ? nil : io
    rescue => e
      logger.debug "Error with URL upload"
      logger.debug e
      return false
    end
  end
   
  def save_dimensions
    if ["image/jpeg", "image/tiff", "image/png", "image/gif", "image/bmp"].include?(upload.content_type.to_s)      
      tempfile = upload.queued_for_write[:original]
      unless tempfile.nil?
        geometry = Paperclip::Geometry.from_file(tempfile)
        self.width = geometry.width.to_i
        self.height = geometry.height.to_i
      end
    end
    self.status = :available
  end
  
  #this gets the upload, detects what it is, and converts to a tif, if necessary.
  #Although an uploaded tif with existing geo fields may confuse things
  def setup_image
    logger.info "setup_image "
    self.filename = upload.original_filename
    save!
    if self.upload?
      
      if  defined?(MAX_DIMENSION) && (width > MAX_DIMENSION || height > MAX_DIMENSION)
        logger.info "Image is too big, so going to resize "
        if width > height
          dest_width = MAX_DIMENSION
          dest_height = (dest_width.to_f /  width.to_f) * height.to_f
        else
          dest_height = MAX_DIMENSION
          dest_width = (dest_height.to_f /  height.to_f) * width.to_f
        end
        self.width = dest_width
        self.height = dest_height
        save!
        outsize = "-outsize #{dest_width.to_i} #{dest_height.to_i}"
      else
        outsize = ""
      end
      
      orig_ext = File.extname(self.upload_file_name).to_s.downcase
      
      tiffed_filename = (orig_ext == ".tif" || orig_ext == ".tiff")? self.upload_file_name : self.upload_file_name + ".tif"
      tiffed_file_path = File.join(maps_dir , tiffed_filename)
      
      logger.info "We convert to tiff"
      # -co compress=DEFLATE for compression?
      # -expand rgb   for tifs with LZW compression. sigh
      command  = "#{GDAL_PATH}gdal_translate #{self.upload.path} #{outsize} -co PHOTOMETRIC=RGB -co PROFILE=BASELINE #{tiffed_file_path}"
      logger.info command
      ti_stdin, ti_stdout, ti_stderr =  Open3::popen3( command )
      logger.info ti_stdout.readlines.to_s
      logger.info ti_stderr.readlines.to_s
      
      command = "#{GDAL_PATH}gdaladdo -r average #{tiffed_file_path} 2 4 8 16 32 64"
      o_stdin, o_stdout, o_stderr = Open3::popen3(command)
      logger.info command
      
      o_out = o_stdout.readlines.to_s
      o_err = o_stderr.readlines.to_s
      if o_stderr.readlines.empty? && o_err.size > 0
        logger.error "Error gdal overview script" + o_err.inspect
        logger.error "output = "+o_out
      end
      
      self.filename = tiffed_filename
      
      #now delete the original
      logger.debug "Deleting uploaded file, now it's a usable tif"
      if File.exists?(self.upload.path)
        logger.debug "deleted uploaded file"
        File.delete(self.upload.path)
      end
      
    end
    self.map_type = :is_map
    self.rough_state = :step_1
    save!
  end
  
  #paperclip plugin deletes the images when model is destroyed
  def delete_images
    logger.info "Deleting map images"
    if File.exists?(temp_filename)
      logger.info "deleted temp"
      File.delete(temp_filename)
    end
    if File.exists?(warped_filename)
      logger.info "Deleted Map warped"
      File.delete(warped_filename)
    end
    if File.exists?(warped_png)
      logger.info "deleted warped png"
      File.delete(warped_png)
    end
    if File.exists?(unwarped_filename)
      logger.info "deleting unwarped"
      File.delete unwarped_filename
    end
  end
  
  def delete_map
    logger.info "Deleting mapfile"
  end
  
  def update_layer
    #    self.layers.each do |layer|
    #      layer.update_layer
    #    end unless self.layers.empty?
  end
  
  def update_layers
    #    logger.info "updating (visible) layers"
    #    unless self.layers.visible.empty?
    #      self.layers.visible.each  do |layer|
    #        layer.update_layer
    #      end
    #    end
  end
  
  def update_counter_cache
    #    logger.info "update_counter_cache"
    #    unless self.layers.empty?
    #      self.layers.each do |layer|
    #        layer.update_counts
    #      end
    #    end
  end
  
  #method to publish the map
  #sets status to published
  def publish
    self.status = :published
    self.save
  end
  
  #unpublishes a map, sets it's status to warped
  def unpublish
    self.status = :warped
    self.save
  end
  
  #############################################
  #CLASS METHODS
  #############################################

  def self.map_type_hash
    values = Map::MAP_TYPE
    keys = ["Index/Overview", "Is a map", "Not a map"]
    Hash[*keys.zip(values).flatten]
  end
  
  def self.max_attachment_size
    max_attachment_size =  defined?(MAX_ATTACHMENT_SIZE)? MAX_ATTACHMENT_SIZE : nil
  end
  
  def self.max_dimension
    max_dimension = defined?(MAX_DIMENSION)? MAX_DIMENSION : nil
  end
  
  #############################################
  #ACCESSOR METHODS
  #############################################

  def maps_dir
    defined?(SRC_MAPS_DIR) ? SRC_MAPS_DIR :  File.join(Rails.root, "/public/mapimages/src/")
  end

  def dest_dir
    defined?(DST_MAPS_DIR) ?  DST_MAPS_DIR : File.join(Rails.root, "/public/mapimages/dst/")
  end


  def warped_dir
    dest_dir
  end

  def unwarped_filename
    File.join(maps_dir, self.filename)
  end

  def warped_filename
    File.join(warped_dir, id.to_s) + ".tif"
  end

  def warped_png_dir
    File.join(dest_dir, "/png/")
  end

  def warped_png
    unless File.exists?(warped_png_filename)
      convert_to_png
    end
    warped_png_filename
  end
  
  def warped_png_filename
    filename = File.join(warped_png_dir, id.to_s) + ".png"
  end

  def warped_png_aux_xml
    warped_png + ".aux.xml"
  end

  def public_warped_tif_url
    "mapimages/dst/"+id.to_s + ".tif"
  end
  
  def public_warped_png_url
    public_warped_tif_url + ".png"
  end

  def mask_file_format
    "gml"
  end

  def temp_filename
    # self.full_filename  + "_temp"
    File.join(warped_dir, id.to_s) + "_temp"
  end

  def masking_file_gml
    File.join(Rails.root, "/public/mapimages/",  self.id.to_s) + ".gml"
  end

  #file made when rasterizing
  def masking_file_gfs
    File.join(Rails.root, "/public/mapimages/",  self.id.to_s) + ".gfs"
  end

  def masked_src_filename
    self.unwarped_filename + "_masked";
  end
  
  
  #############################################
  #INSTANCE METHODS
  #############################################
  
  
  def depicts_year
    self.layers.with_year.collect(&:depicts_year).compact.first
  end
  
  def warped?
    status == :warped
  end
  
  def available?
    return [:available,:warping, :warped, :published].include?(status)
  end

  def published?
    status == :published
  end

  def warped_or_published?
    return [:warped, :published].include?(status)
  end
  
  def last_changed
    if self.gcps.size > 0
      self.gcps.last.created_at
    elsif !self.updated_at.nil?
      self.updated_at
    elsif !self.created_at.nil?
      self.created_at
    else
      Time.now
    end
  end
  
  
  #attempts to align based on the extent and offset of the
  #reference map's warped image
  #results it nicer gcps to edit with later
  def align_with_warped (srcmap, align = nil, append = false)
    srcmap = Map.find(srcmap)
    origgcps = srcmap.gcps.hard

    #clear out original gcps, unless we want to append the copied gcps to the existing ones
    self.gcps.hard.destroy_all unless append == true

    #extent of source from gdalinfo
    stdin, stdout, sterr = Open3::popen3("#{GDAL_PATH}gdalinfo #{srcmap.warped_filename}")
    info = stdout.readlines.to_s
    stringLW,west,south = info.match(/Lower Left\s+\(\s*([-.\d]+), \s+([-.\d]+)/).to_a
    stringUR,east,north = info.match(/Upper Right\s+\(\s*([-.\d]+), \s+([-.\d]+)/).to_a

    lon_shift = west.to_f - east.to_f
    lat_shift = south.to_f - north.to_f

    origgcps.each do |gcp|
      a = Gcp.new()
      a = gcp.clone
      if align == "east"
        a.lon -= lon_shift
      elsif align == "west"
        a.lon += lon_shift
      elsif align == "north"
        a.lat -= lat_shift
      elsif align == "south"
        a.lat += lat_shift
      else
        #if no align, then dont change the gcps
      end
      a.map = self
      a.save
    end

    newgcps = self.gcps.hard
  end

  #attempts to align based on the width and height of
  #reference map's un warped image
  #results it potential better fit than align_with_warped
  #but with less accessible gpcs to edit
  def align_with_original(srcmap, align = nil, append = false)
    srcmap = Map.find(srcmap)
    origgcps = srcmap.gcps

    #clear out original gcps, unless we want to append the copied gcps to the existing ones
    self.gcps.hard.destroy_all unless append == true

    origgcps.each do |gcp|
      new_gcp = Gcp.new()
      new_gcp = gcp.clone
      if align == "east"
        new_gcp.x -= srcmap.width

      elsif align == "west"
        new_gcp.x += srcmap.width
      elsif align == "north"
        new_gcp.y += srcmap.height
      elsif align == "south"
        new_gcp.y -= srcmap.height
      else
        #if no align, then dont change the gcps
      end
      new_gcp.map = self
      new_gcp.save
    end

    newgcps = self.gcps.hard
  end
  
  # map gets error attibute set and gcps get error attribute set
  def gcps_with_error(soft=nil)
    unless soft == 'true'
      gcps = Gcp.hard.find(:all, :conditions =>["map_id = ?", self.id], :order => 'created_at')
    else
      gcps = Gcp.soft.find(:all, :conditions =>["map_id = ?", self.id], :order => 'created_at')
    end
    gcps, map_error = ErrorCalculator::calc_error(gcps)
    @error = map_error
    #send back the gpcs with error calculation
    gcps
  end

  def mask!

    self.mask_status = :masking
    save!
    format = self.mask_file_format

    if format == "gml"
      return "no masking file found, have you created a clipping mask and saved it?"  if !File.exists?(masking_file_gml)
      masking_file = self.masking_file_gml
      layer = "features"
    elsif format == "json"
      return "no masking file found, have you created a clipping mask and saved it?"  if !File.exists?(masking_file_json)
      masking_file = self.masking_file_json
      layer = "OGRGeoJson"
    else
      return "no masking file matching specified format found."
    end

    masked_src_filename = self.masked_src_filename
    if File.exists?(masked_src_filename)
      #deleting old masked image
      File.delete(masked_src_filename)
    end
    #copy over orig to a new unmasked file
    File.copy(unwarped_filename, masked_src_filename)
    #TODO ADD -i switch when we have newer gdal
    require 'open3'
    r_stdin, r_stdout, r_stderr = Open3::popen3(
      "#{GDAL_PATH}gdal_rasterize -i  -burn 17 -b 1 -b 2 -b 3 #{masking_file} -l #{layer} #{masked_src_filename}"
    )
    logger.info "#{GDAL_PATH}gdal_rasterize -i  -burn 17 -b 1 -b 2 -b 3 #{masking_file} -l #{layer} #{masked_src_filename}"
    r_out  = r_stdout.readlines.to_s
    r_err = r_stderr.readlines.to_s

    #if there is an error, and it's not a warning about SRS
    if r_err.size > 0 && r_err.split[0] != "Warning"
      #error, need to fail nicely
      logger.error "ERROR gdal rasterize script: "+ r_err
      logger.error "Output = " +r_out
      r_out = "ERROR with gdal rasterise script: " + r_err + "<br /> You may want to try it again? <br />" + r_out

    else

      r_out = "Success! Map was cropped!"
    end

    self.mask_status = :masked
    save!
    r_out
  end
  #
  # FIXME -clear up this method - don't return the text, just raise execption if necessary
  #
  # gdal_rasterize -i -burn 17 -b 1 -b 2 -b 3 SSS.json -l OGRGeoJson orig.tif
  # gdal_rasterize -burn 17 -b 1 -b 2 -b 3 SSS.gml -l features orig.tif

  #Main warp method
  def warp!(resample_option, transform_option, use_mask="false")
    prior_status = self.status
    self.status = :warping
    save!
    
    gcp_array = self.gcps.hard
    
    gcp_string = ""
    
    gcp_array.each do |gcp|
      gcp_string = gcp_string + gcp.gdal_string
    end
    
    mask_options = ""
    if use_mask == "true" && self.mask_status == :masked
      src_filename = self.masked_src_filename
      mask_options = " -srcnodata '17 17 17' "
    else
      src_filename = self.unwarped_filename
    end
    
    dest_filename = self.warped_filename
    temp_filename = self.temp_filename
    
    #delete existing temp images @map.delete_images
    if File.exists?(dest_filename)
      #logger.info "deleted warped file ahead of making new one"
      File.delete(dest_filename)
    end
    
    logger.info "gdal translate"
    
    t_stdin, t_stdout, t_stderr = Open3::popen3(
      "#{GDAL_PATH}gdal_translate -a_srs '+init=epsg:4326' -of VRT #{src_filename} #{temp_filename}.vrt #{gcp_string}"
    )
    
    logger.info "#{GDAL_PATH}gdal_translate -a_srs '+init=epsg:4326' -of VRT #{src_filename} #{temp_filename}.vrt #{gcp_string}"
    t_out  = t_stdout.readlines.to_s
    t_err = t_stderr.readlines.to_s
    
    if t_err.size > 0
      logger.error "ERROR gdal translate script: "+ t_err
      logger.error "Output = " +t_out
      t_out = "ERROR with gdal translate script: " + t_err + "<br /> You may want to try it again? <br />" + t_out
    else
      t_out = "Okay, translate command ran fine! <div id = 'scriptout'>" + t_out + "</div>"
    end
    trans_output = t_out
    
    memory_limit =  (defined?(GDAL_MEMORY_LIMIT)) ? "-wm "+GDAL_MEMORY_LIMIT.to_s :  ""
    
    #check for colorinterop=pal ? -disnodata 255 or -dstalpha
    command = "#{GDAL_PATH}gdalwarp #{memory_limit}  #{transform_option}  #{resample_option} -dstalpha #{mask_options} -s_srs 'EPSG:4326' #{temp_filename}.vrt #{dest_filename} -co TILED=YES -co COMPRESS=LZW"
    w_stdin, w_stdout, w_stderr = Open3::popen3(command)
    logger.info command
    
    w_out = w_stdout.readlines.to_s
    w_err = w_stderr.readlines.to_s
    if w_err.size > 0
      logger.error "Error gdal warp script" + w_err
      logger.error "output = "+w_out
      w_out = "error with gdal warp: "+ w_err +"<br /> try it again?<br />"+ w_out
    else
      w_out = "Okay, warp command ran fine! <div id='scriptout'>" + w_out +"</div>"
    end
    warp_output = w_out
    
    # gdaladdo
    command = "#{GDAL_PATH}gdaladdo -r average #{dest_filename} 2 4 8 16 32 64"
    o_stdin, o_stdout, o_stderr = Open3::popen3(command)
    logger.info command
    
    o_out = o_stdout.readlines.to_s
    o_err = o_stderr.readlines.to_s
    if o_err.size > 0
      logger.error "Error gdal overview script" + o_err
      logger.error "output = "+o_out
      o_out = "error with gdal overview: "+ o_err +"<br /> try it again?<br />"+ o_out
    else
      o_out = "Okay, overview command ran fine! <div id='scriptout'>" + o_out +"</div>"
    end
    overview_output = o_out
    
    if File.exists?(temp_filename + '.vrt')
      logger.info "deleted temp vrt file"
      File.delete(temp_filename + '.vrt')
    end
    
    # don't care too much if overviews threw a random warning
    if w_err.size <= 0 and t_err.size <= 0
      if prior_status == :published
        self.status = :published
      else
        self.status = :warped
      end
      Spawnling.new do
        convert_to_png
      end
      self.touch(:rectified_at)
    else
      self.status = :available
    end
    save!
    update_layers
    update_bbox
    output = "Step 1: Translate: "+ trans_output + "<br />Step 2: Warp: " + warp_output + \
      "Step 3: Add overviews:" + overview_output
  end
  
  ############
  #PRIVATE
  ############
  
  def convert_to_png
    logger.info "start convert to png ->  #{warped_png_filename}"
    ext_command = "#{GDAL_PATH}gdal_translate -of png #{warped_filename} #{warped_png_filename}"
    stdin, stdout, stderr = Open3::popen3(ext_command)
    logger.debug ext_command
    if stderr.readlines.to_s.size > 0
      logger.error "ERROR convert png #{warped_filename} -> #{warped_png_filename}"
      logger.error stderr.readlines.to_s
      logger.error stdout.readlines.to_s
    else
      logger.info "end, converted to png -> #{warped_png_filename}"
    end
  end

  
end