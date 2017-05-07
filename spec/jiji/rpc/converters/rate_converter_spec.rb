# coding: utf-8

require 'jiji/test/test_configuration'
require 'jiji/test/data_builder'

describe Jiji::Rpc::Converters::RateConverter do
  include_context 'use data_builder'

  class Converter

    include Jiji::Rpc::Converters

  end

  let(:converter) { Converter.new }

  describe '#convert_rate_to_pb' do
    it 'converts an array of Rate to Rpc::Rates' do
      rates = [
        Jiji::Model::Trading::Rate.create_from_tick(:EURJPY,
          data_builder.new_tick(1,   Time.utc(2014, 1, 1, 0, 0, 0)),
          data_builder.new_tick(2,   Time.utc(2014, 2, 1, 0, 0, 0)),
          data_builder.new_tick(3,   Time.utc(2014, 1, 1, 0, 0, 1)),
          data_builder.new_tick(10,  Time.utc(2014, 1, 10, 0, 0, 0)),
          data_builder.new_tick(-10, Time.utc(2014, 1, 21, 0, 0, 0))
        ),
        Jiji::Model::Trading::Rate.create_from_tick(:EURJPY,
          data_builder.new_tick(1,   Time.utc(2015, 1, 1, 0, 0, 0)),
          data_builder.new_tick(2,   Time.utc(2015, 2, 1, 0, 0, 0)),
          data_builder.new_tick(3,   Time.utc(2015, 1, 1, 0, 0, 1)),
          data_builder.new_tick(10,  Time.utc(2015, 1, 10, 0, 0, 0)),
          data_builder.new_tick(-10, Time.utc(2015, 1, 21, 0, 0, 0))
        )
      ]
      converted = converter.convert_rates_to_pb(rates)
      expect(converted.rates.length).to eq(2)

      converted = converter.convert_rates_to_pb([])
      expect(converted.rates.length).to eq(0)
    end
    it 'returns nil when an array of Rate is nil' do
      converted = converter.convert_rates_to_pb(nil)
      expect(converted).to eq nil
    end
  end

  describe '#convert_rate_to_pb' do
    it 'converts Rate to Rpc::Rate' do
      rate = Jiji::Model::Trading::Rate.create_from_tick(:EURJPY,
        data_builder.new_tick(1,   Time.utc(2014, 1, 1, 0, 0, 0)),
        data_builder.new_tick(2,   Time.utc(2014, 2, 1, 0, 0, 0)),
        data_builder.new_tick(3,   Time.utc(2014, 1, 1, 0, 0, 1)),
        data_builder.new_tick(10,  Time.utc(2014, 1, 10, 0, 0, 0)),
        data_builder.new_tick(-10, Time.utc(2014, 1, 21, 0, 0, 0))
      )
      converted = converter.convert_rate_to_pb(rate)
      expect(converted.pair).to eq('EURJPY')
      expect(converted.open.bid.value).to eq('101.0')
      expect(converted.open.ask.value).to eq('101.003')
      expect(converted.close.bid.value).to eq('102.0')
      expect(converted.close.ask.value).to eq('102.003')
      expect(converted.high.bid.value).to eq('110.0')
      expect(converted.high.ask.value).to eq('110.003')
      expect(converted.low.bid.value).to eq('90.0')
      expect(converted.low.ask.value).to eq('90.003')
      expect(converted.timestamp.seconds).to eq 1_388_534_400
      expect(converted.timestamp.nanos).to be 0
    end
    it 'returns nil when a rate is nil' do
      converted = converter.convert_rate_to_pb(nil)
      expect(converted).to eq nil
    end
  end
end
