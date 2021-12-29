using Base: String, Bool, Float64
abstract type AbstractEntity end

mutable struct Account <: AbstractEntity
    id::String
    account_number::String
    status::String
    currency::String
    cash::Float64
    portfolio_value::Float64
    pattern_day_trader::Bool
    trade_suspended_by_user::Bool
    trading_blocked::Bool
    transfers_blocked::Bool
    account_blocked::Bool
    created_at::DateTime
    shorting_enabled::Bool
    long_market_value::Float64
    short_market_value::Float64
    equity::Float64
    last_equity::Float64
    multiplier::Float64
    buying_power::Float64
    initial_margin::Float64
    maintainance_margin::Float64
    sma::Float64
    daytrade_count::Int
    last_maintainance_margin::Float64
    daytrading_buying_power::Float64
    regt_buying_power::Float64
end

mutable struct AccountConfigurations <: AbstractEntity
    dtbp_check::String
    trade_confirm_email::String
    suspend_trade::Bool
    no_shorting::Bool
end

mutable struct Asset <: AbstractEntity
    id::String
    class::String
    exchange::String
    symbol::String
    status::String
    tradable::Bool
    marginable::Bool
    shortable::Bool
    easy_to_borrow::Bool
    fractionable::Bool
end

mutable struct Order{Tl} <: AbstractEntity
    id::String
    client_order_id::String
    created_at::DateTime
    updated_at::Maybe{DateTime}
    submitted_at::Maybe{DateTime}
    filled_at::Maybe{DateTime}
    expired_at::Maybe{DateTime}
    canceled_at::Maybe{DateTime}
    failed_at::Maybe{DateTime}
    replaced_at::Maybe{DateTime}
    replaces::Maybe{String}
    asset_id::String
    symbol::String
    asset_class::String
    notional::Float64
    qty::Float64
    filled_qty::Float64
    filled_avg_price::Maybe{Float64}
    order_class::String
    order_type::String
    type::String
    side::String
    time_in_force::String
    limit_price::Maybe{Float64}
    stop_price::Maybe{Float64}
    status::String
    extended_hours::Bool
    legs::Vector{Tl}
    trail_percent::Float64
    trail_price::Float64
    hwm::Float64
end

mutable struct Position <: AbstractEntity
    asset_id::String
    symbol::String
    exchange::String
    asset_class::String
    avg_entry_price::Float64
    qty::Int
    side::String
    market_value::Float64
    cost_basis::Float64
    unrealized_pl::Float64
    unrealized_plpc::Float64
    unrealized_intraday_pl::Float64
    unrealized_intraday_plpc::Float64
    current_price::Float64
    lastday_price::Float64
    change_today::Float64
end

abstract type AccountActivity <: AbstractEntity end

mutable struct TradeActivity <: AccountActivity
    activity_type::String
    id::String
    cum_qty::Float64
    leaves_qty::Float64
    price::Float64
    qty::Float64
    side::String
    symbol::String
    transaction_time::DateTime
    order_id::String
    type::String
end

mutable struct NonTradeActivity <: AccountActivity
    activity_type::String
    id::String
    date::DateTime
    net_amount::Float64
    symbol::String
    qty::Float64
    per_share_amount::Float64
end

mutable struct Bar <: AbstractEntity
    symbol::String
    t::DateTime
    o::Float64
    h::Float64
    l::Float64
    c::Float64
    v::Int
    n::Int
    vw::Float64
end

mutable struct Trade <: AbstractEntity
    symbol::String
    t::DateTime
    x::String
    p::Float64
    s::Int
    c::String
    i::Int
    z::String
end

mutable struct Quote <: AbstractEntity
    symbol::String
    t::DateTime
    ax::String
    ap::Float64
    as::Int
    bx::String
    bp::Float64
    bs::Int
    c::String
end
