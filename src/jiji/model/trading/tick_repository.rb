# coding: utf-8

require 'encase'

module Jiji
module Model
module Trading

  class TickRepository
    
    include Encase
    include Jiji::Errors
    
    def fetch( start_time, end_time )
      swaps = Internal::Swaps.create( start_time, end_time )
      return Tick.where({
        :timestamp.gte => start_time, 
        :timestamp.lt  => end_time 
      }).order_by(:timestamp.asc).map {|t|
        t.swaps = swaps.get_swaps_at( t.timestamp )
        t
      }
    end
    
    def range
      return {:start=>nil, :end=>nil} unless Tick.exists?
      
      first = Tick.order_by(:timestamp.asc).only(:timestamp).first
      last  = Tick.order_by(:timestamp.asc).only(:timestamp).last
      return {:start=> first.timestamp, :end=>last.timestamp}
    end
    
    def delete( start_time, end_time )
      Tick.where({
        :timestamp.gte => start_time, 
        :timestamp.lt  => end_time 
      }).delete
    end
    
  end 

end
end
end
