class Gcp < ActiveRecord::Base
belongs_to :map

acts_as_audited
validates_numericality_of :x, :y, :lat, :lon
validates_presence_of :x, :y, :lat, :lon, :map_id

named_scope  :soft, :conditions => {:soft => true}
named_scope  :hard, :conditions => ["gcps.soft IS NULL OR gcps.soft = 'F'"]

attr_accessor :error

def gdal_string
	
gdal_string = " -gcp " + x.to_s + ", " + y.to_s + ", " + lon.to_s + ", " + lat.to_s

end

end


