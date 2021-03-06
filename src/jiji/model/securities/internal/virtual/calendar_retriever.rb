# frozen_string_literal: true

module Jiji::Model::Securities::Internal::Virtual
  module CalendarRetriever
    def retrieve_calendar(period, pair_name = nil)
      @securities_provider.get.retrieve_calendar(period, pair_name)
    end
  end
end
