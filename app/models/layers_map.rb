# To change this template, choose Tools | Templates
# and open the template in the editor.

class LayersMap < ActiveRecord::Base
  belongs_to :layer
  belongs_to :map
end
