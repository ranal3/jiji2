# frozen_string_literal: true

require 'jiji/model/securities/internal/utils/converter'

module Jiji::Model::Securities::Internal::Oanda
  module Ordering
    include Jiji::Errors
    include Jiji::Model::Trading
    include Jiji::Model::Trading::Utils
    include Jiji::Model::Securities::Internal::Utils

    def order(pair_name, sell_or_buy, units, type = :market, options = {})
      options = Converter.convert_option_to_oanda(options)
      @order_validator.validate(pair_name, sell_or_buy, units, type, options)
      response = @client.account(@account['id']).order({
        order: {
          instrument: Converter.convert_pair_name_to_instrument(pair_name),
          type:       Converter.convert_order_type_to_oanda(type),
          units:      sell_or_buy === :buy ? units : units * -1
        }.merge(options)
      }).create
      convert_response_to_order_result(response, type)
    end

    def retrieve_orders(count = 500, pair_name = nil, max_id = nil)
      param = { count: count }
      if pair_name
        param[:instrument] =
          Converter.convert_pair_name_to_instrument(pair_name)
      end
      param[:max_id] = max_id if max_id
      @client.account(@account['id'])
        .orders(param).show['orders'].reject do |item|
        %w[TRAILING_STOP_LOSS TAKE_PROFIT STOP_LOSS].include?(item['type'])
      end.map do |item|
        convert_response_to_order(item)
      end
    end

    def retrieve_order_by_id(internal_id)
      response = @client.account(@account['id'])
        .order(internal_id).show
      convert_response_to_order(response['order'])
    end

    def modify_order(internal_id, options = {})
      order = retrieve_order_by_id(internal_id)
      options = Converter.convert_option_to_oanda(options)
      options[:type] = Converter.convert_order_type_to_oanda(order.type)
      options[:instrument] = Converter.convert_pair_name_to_instrument(order.pair_name)
      options[:price] = options[:price] || order.price
      options[:units] = options[:units] || order.units
      @order_validator.validate(order.pair_name, order.sell_or_buy, options[:units] || order.units, order.type, options)
      options[:units] = order.sell_or_buy === :buy ? options[:units] : options[:units] * -1
      response = @client.account(@account['id'])
        .order(internal_id, { order: options }).update
      convert_response_to_order(response['orderCreateTransaction'])
    end

    def cancel_order(internal_id)
      order = retrieve_order_by_id(internal_id)
      response = @client.account(@account['id'])
        .order(internal_id).cancel
      order
    end

    private

    def convert_response_to_order_result(res, type)
      order_opened = res['orderFillTransaction'] ? nil : convert_response_to_order(res['orderCreateTransaction'], type)
      trade_opened = nil
      trade_reduced = nil
      trades_closed = []
      tx = res['orderFillTransaction']
      if tx
        if tx['tradeOpened']
          trade_opened = retrieve_trade_by_id(tx['tradeOpened']['tradeID'])
          trade_opened.update_price(retrieve_current_tick, account_currency)
        end
        if tx['tradeReduced']
          trade_reduced = convert_response_to_reduced_position(tx['tradeReduced'], tx['time'])
        end
        if tx['tradesClosed']
          trades_closed = tx['tradesClosed'].map do |r|
            convert_response_to_closed_position(r, tx['time'])
          end
        end
      end
      OrderResult.new(order_opened, trade_opened, trade_reduced, trades_closed)
    end

    def convert_response_to_order(res, type = nil)
      pair_name = res['instrument'] ? Converter.convert_instrument_to_pair_name(res['instrument']) : nil
      t = type || Converter.convert_order_type_from_oanda(res['type'])
      order = Order.new(pair_name, res['id'].to_s,
        PricingUtils.detect_sell_or_buy(res['units']), t, Time.parse(res['time'] || res['createTime']))
      copy_options(order, res, t)
      order
    end

    def convert_trade_opened_to_position(trade_opened, type = nil)
      pair_name = Converter.convert_instrument_to_pair_name(trade_opened['instrument'])
      t = type || Converter.convert_order_type_from_oanda(res['type'])
      order = Order.new(pair_name, res['id'].to_s,
        PricingUtils.detect_sell_or_buy(res['units']), t, Time.parse(res['time']))
      copy_options(order, res, t)
      order
    end

    def convert_response_to_reduced_position(detail, time)
      # trade_reducedからは損益は取得できない。ローカルで計算した近似値を使う
      ReducedPosition.new(detail['tradeID'],
        detail['units'].to_i.abs, BigDecimal(detail['price'], 10), Time.parse(time), nil)
    end

    def convert_response_to_closed_position(detail, time)
      # trade_closedからは損益は取得できない。ローカルで計算した近似値を使う
      ClosedPosition.new(detail['tradeID'],
        detail['units'].to_i.abs, BigDecimal(detail['price'], 10), Time.parse(time), nil)
    end

    def copy_options(order, detail, type)
      order.units = detail['units'].to_i.abs
      %w[
        timeInForce positionFill triggerCondition
        clientExtensions takeProfitOnFill stopLossOnFill
        trailingStopLossOnFill tradeClientExtensions gtdTime
        priceBound price
      ].each do |key|
        order.send("#{key.underscore.downcase}=",
          Converter.convert_option_value_from_oanda(key, detail[key]))
      end
    end
  end
end
