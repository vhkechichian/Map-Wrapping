class LayersMap < ActiveRecord::Base
  belongs_to :layer
  belongs_to :map

  validates_uniqueness_of :layer_id, :scope => :map_id, :message => "already has this map"
end
