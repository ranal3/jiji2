# frozen_string_literal: true

# === トラップリピートイフダンのような注文を発行するエージェント
class TrapRepeatIfDoneAgent

  include Jiji::Model::Agents::Agent

  def self.description
    <<~STR
      トラップリピートイフダンのような注文を発行するエージェント
    STR
  end

  # UIから設定可能なプロパティの一覧
  def self.property_infos
    [
      Property.new('trap_interval_pips', 'トラップを仕掛ける間隔(pips)', 50),
      Property.new('trade_units',        '1注文あたりの取引数量',         1),
      Property.new('profit_pips',        '利益を確定するpips',         100)
    ]
  end

  def post_create
    @trap_repeat_if_done = TrapRepeatIfDone.new(
      broker.pairs.find { |p| p.name == :USDJPY }, :buy,
      @trap_interval_pips.to_i,
      @trade_units.to_i, @profit_pips.to_i, logger)
  end

  def next_tick(tick)
    @trap_repeat_if_done.register_orders(broker)
  end

  def state
    @trap_repeat_if_done.state
  end

  def restore_state(state)
    @trap_repeat_if_done.restore_state(state)
  end

end

# トラップリピートイフダンのような注文を発行するクラス
class TrapRepeatIfDone

  # コンストラクタ
  #
  # target_pair:: 現在の価格を格納するTick::Valueオブジェクト
  # sell_or_buy:: 取引モード。 :buy の場合、買い注文を発行する。 :sellの場合、売
  # trap_interval_pips:: トラップを仕掛ける間隔(pips)
  # trade_units:: 1注文あたりの取引数量
  # profit_pips:: 利益を確定するpips
  def initialize(target_pair, sell_or_buy = :buy, trap_interval_pips = 50,
    trade_units = 1, profit_pips = 100, logger = nil)

    @target_pair        = target_pair
    @trap_interval_pips = trap_interval_pips
    @mode               = create_mode(target_pair, sell_or_buy,
      trade_units, profit_pips, logger)

    @logger = logger
    @registerd_orders = {}
  end

  # 注文を登録する
  #
  # broker:: broker
  def register_orders(broker)
    broker.refresh_positions
    # 常に最新の建玉を取得して利用するようにする

    each_traps(broker.tick) do |trap_open_price|
      next if order_or_position_exists?(trap_open_price, broker)

      register_order(trap_open_price, broker)
    end
  end

  def state
    @registerd_orders
  end

  def restore_state(state)
    @registerd_orders = state unless state.nil?
  end

  private

  def each_traps(tick)
    current_price = @mode.resolve_current_price(tick[@target_pair.name])
    base = resolve_base_price(current_price)
    6.times do |n| # baseを基準に、上下3つのトラップを仕掛ける
      trap_open_price = BigDecimal(base, 10) \
        + BigDecimal(@trap_interval_pips, 10) * (n - 3) * @target_pair.pip
      yield trap_open_price
    end
  end

  # 現在価格をtrap_interval_pipsで丸めた価格を返す。
  #
  #  例) trap_interval_pipsが50の場合、
  #  resolve_base_price(120.10) # -> 120.00
  #  resolve_base_price(120.49) # -> 120.00
  #  resolve_base_price(120.51) # -> 120.50
  #
  def resolve_base_price(current_price)
    current_price = BigDecimal(current_price, 10)
    pip_precision = 1 / @target_pair.pip
    (current_price * pip_precision / @trap_interval_pips).ceil \
      * @trap_interval_pips / pip_precision
  end

  # trap_open_priceに対応するオーダーを登録する
  def register_order(trap_open_price, broker)
    result = @mode.register_order(trap_open_price, broker)
    unless result.order_opened.nil?
      @registerd_orders[key_for(trap_open_price)] \
        = result.order_opened.internal_id
    end
  end

  # trap_open_priceに対応するオーダーを登録済みか評価する
  def order_or_position_exists?(trap_open_price, broker)
    order_exists?(trap_open_price, broker) \
    || position_exists?(trap_open_price, broker)
  end

  def order_exists?(trap_open_price, broker)
    key = key_for(trap_open_price)
    return false unless @registerd_orders.include? key

    id = @registerd_orders[key]
    order = broker.orders.find { |o| o.internal_id == id }
    !order.nil?
  end

  def position_exists?(trap_open_price, broker)
    # trapのリミット付近でレートが上下して注文が大量に発注されないよう、
    # trapのリミット付近を開始値とする建玉が存在する間は、trapの注文を発行しない
    slipage_price = 10 * @target_pair.pip
    position = broker.positions.find do |p|
      # 注文時に指定したpriceちょうどで約定しない場合を考慮して、
      # 10pipsの誤差を考慮して存在判定をする
      p.entry_price < trap_open_price + slipage_price \
      && p.entry_price > trap_open_price - slipage_price
    end
    !position.nil?
  end

  def key_for(trap_open_price)
    (trap_open_price * (1 / @target_pair.pip)).to_i.to_s
  end

  def create_mode(target_pair, sell_or_buy,
    trade_units, profit_pips, logger)
    if sell_or_buy == :sell
      Sell.new(target_pair, trade_units, profit_pips, logger)
    else
      Buy.new(target_pair, trade_units, profit_pips, logger)
    end
  end

  # 取引モード(売 or 買)
  # 買(Buy)の場合、買でオーダーを行う。売(Sell)の場合、売でオーダーを行う。
  class Mode

    def initialize(target_pair, trade_units, profit_pips, logger)
      @target_pair  = target_pair
      @trade_units  = trade_units
      @profit_pips  = profit_pips
      @logger       = logger
    end

    # 現在価格を取得する(買の場合Askレート、売の場合Bidレートを使う)
    #
    # tick_value:: 現在の価格を格納するTick::Valueオブジェクト
    # 戻り値:: 現在価格
    def resolve_current_price(tick_value); end

    # 注文を登録する
    def register_order(trap_open_price, broker); end

    def calculate_price(price, pips)
      price = BigDecimal(price, 10)
      pips  = BigDecimal(pips,  10) * @target_pair.pip
      (price + pips).to_f
    end

    def print_order_log(mode, options, timestamp)
      return unless @logger

      message = [
        mode, timestamp, options[:price], options[:take_profit],
        options[:lower_bound], options[:upper_bound]
      ].map { |item| item.to_s }.join(' ')
      @logger.info message
    end

  end

  class Sell < Mode

    def resolve_current_price(tick_value)
      tick_value.bid
    end

    def register_order(trap_open_price, broker)
      timestamp = broker.tick.timestamp
      options = create_option(trap_open_price, timestamp)
      print_order_log('sell', options, timestamp)
      broker.sell(@target_pair.name, @trade_units, :marketIfTouched, options)
    end

    def create_option(trap_open_price, timestamp)
      {
        price:               trap_open_price.to_f,
        take_profit_on_fill: { price: calculate_price(trap_open_price, @profit_pips * -1) },
        time_in_force:       'GTD',
        gtd_time:            timestamp + 60 * 60 * 24 * 7
      }
    end

  end

  class Buy < Mode

    def resolve_current_price(tick_value)
      tick_value.ask
    end

    def register_order(trap_open_price, broker)
      timestamp = broker.tick.timestamp
      options = create_option(trap_open_price, timestamp)
      print_order_log('buy', options, timestamp)
      broker.buy(@target_pair.name, @trade_units, :marketIfTouched, options)
    end

    def create_option(trap_open_price, timestamp)
      {
        price:               trap_open_price.to_f,
        take_profit_on_fill: { price: calculate_price(trap_open_price, @profit_pips) },
        time_in_force:       'GTD',
        gtd_time:            timestamp + 60 * 60 * 24 * 7
      }
    end

  end

end
