const Positions = Vector{Position}
const Orders = Vector{Order}
const Assets = Vector{Asset}
const AccountActivities = Vector{AccountActivity}

const DATA_V2_MAX_LIMIT = 10_000

struct RetryException <: Exception end

struct RESTParams
    key_id::String
    secret_key::String
    base_url::String
    data_url::String
    retry_max::Int
    retry_wait::Float64
    retry_codes::Vector{Int}
end

function RESTParams(;
        key_id::Maybe{String}=nothing,
        secret_key::Maybe{String}=nothing,
        base_url::Maybe{String}=nothing,
        data_url::Maybe{String}=nothing,
        retry_max::Maybe{<:Integer}=nothing,
        retry_wait::Maybe{<:Real}=nothing,
        retry_codes::Maybe{<:AbstractVector{<:Integer}}=nothing
    )

    if key_id === nothing && haskey(ENV, "APCA_API_KEY_ID")
        key_id = ENV["APCA_API_KEY_ID"]
    end

    if secret_key === nothing && haskey(ENV, "APCA_API_SECRET_KEY")
        secret_key = ENV["APCA_API_SECRET_KEY"]
    end

    if base_url === nothing
        base_url = get(ENV, "APCA_API_BASE_URL", "https://api.alpaca.markets")
    end

    if data_url === nothing
        data_url = get(ENV, "APCA_API_DATA_URL", "https://data.alpaca.markets")
    end

    if retry_max === nothing
        retry_max = get(ENV, "APCA_API_RETRY_MAX", 3)
    end

    if retry_wait === nothing
        retry_wait = get(ENV, "APCA_API_RETRY_WAIT", 3.0)
    end

    if retry_codes === nothing
        retry_codes = get(ENV, "APCA_API_RETRY_CODES", [429,504])
    end

    return RESTParams(
        key_id,
        secret_key,
        base_url,
        data_url,
        retry_max,
        retry_wait,
        retry_codes
    )
end

const API_VERSION = "v2"

const TimeFrameUnit = (Minute="Min", Hour="Hour", Day="Day")

mutable struct TimeFrame
    amount::Int
    unit::String
    function TimeFrame(amount::Int, unit::String)
        !in(unit, TimeFrameUnit) && throw(ArgumentError("Time unit must be in $(repr(TimeFrameUnit))"))
        amount <= 0 && throw(ArgumentError("Amount must be a positive integer value."))
        unit == TimeFrameUnit.Minute && amount > 59 && throw(ArgumentError("Second or Minute units can only be used with amounts between 1 and 59."))
        unit == TimeFrameUnit.Minute && amount > 23 && throw(ArgumentError("Hour units can only be used with amounts between 1 and 23."))

        return new(amount, unit)
    end
end
Base.string(tf::TimeFrame) = string(tf.amount) * tf.unit
JSON.show_json(io::JSON.StructuralContext, ser::JSON.CommonSerialization, tf::TimeFrame) =
    JSON.show_json(io, ser, string(tf))
HTTP.URIs.escapeuri(tf::TimeFrame) = string(tf)
HTTP.URIs.escapeuri(key, value::Nothing) = ""

const REF_TIME_ZONE_STR = "-05:00"
HTTP.URIs.escapeuri(t::DateTime) = string(t) * REF_TIME_ZONE_STR

function generate_header(api::RESTParams)
    return Dict("APCA-API-KEY-ID" => api.key_id, "APCA-API-SECRET-KEY" => api.secret_key)
end

function _request(api::RESTParams, method::String, path::String, data=nothing; base_url=api.base_url)
    url = base_url * "/" * API_VERSION * path

    header = generate_header(api)

    body = ""
    query= ""
    if data !== nothing
        if uppercase(method) in ["GET", "DELETE"]
            body = ""
            query = strip(replace(HTTP.URIs.escapeuri(data), "stop" => "end"), '&')
        else
            body = json(data)
            query = ""
        end
    end

@debug """Sending request:
  method="$method"
  url="$url"
  query="$query"
  header=$header
  body="$body" """

    retry = -1
    retry_max = api.retry_max
    while retry < retry_max
        try
            res = HTTP.request(method, url, header, body; query=query, status_exception=true)

            res_dict = JSON.parse(String(res.body))

            return res_dict
        catch err
            if isa(err, HTTP.StatusError) && in(err.status, api.retry_codes)
                @debug err.status
                retry += 1
                remaining_retries = retry_max - retry
                if remaining_retries > 0
                    @warn "Sleeping $(api.retry_wait) seconds and retrying $(url) $(remaining_retries) more time(s)"
                    sleep(api.retry_wait)
                end
            else
                rethrow(err)
            end
        end
    end

    nothing
end

Base.convert(::Type{DateTime}, s::String) = DateTime(s, dateformat"yyyy-mm-ddTH:M:SZ")
function wrap_response(::Type{T}, res::AbstractDict) where {T <: AbstractEntity}
    fn = fieldnames(T)
    ft = fieldtypes(T)

    return T([get(res, String(n), nothing) for (n, t) in zip(fn, ft)]...)
end

## Live Trading

function get_assets(api::RESTParams; status::Maybe{<:AbstractString}=nothing, asset_class::Maybe{<:AbstractString}="us_equity")

    params = (status=status, asset_class=asset_class)

    assets = _request(api, "GET", "/assets", params)

    return (wrap_response(Asset, asset) for asset in assets)
end

function get_account(api::RESTParams)
    return wrap_response(Account, _request(api, "GET", "/account"; base_url=api.base_url))
end

function get_account_configuration(api::RESTParams)
    return wrap_response(AccountConfiguration, _request(api, "GET", "/account/configurations"; base_url=api.base_url))
end

function update_account_configurations(api::RESTParams; kwargs...)

    return wrap_response(AccountConfiguration, _request(api, "PATCH", "/account/configurations", kwargs))
end

function list_orders(api::RESTParams; kwargs...)
    orders = _request(api, "GET", "/orders", kwargs)

    return [wrap_response(Order, order) for order in orders]
end

function submit_order(api::RESTParams; kwargs...)

    default_params = (
        :side => "buy",
        :type => "market",
        :time_in_force => "day"
    )

    params = merge(default_params, NamedTuple(kwargs))

    res = _request(api, "POST", "/orders", params)

    return wrap_response(Order, res)
end





## Historical data

#todo Make a generator/iterator version of this
function _data_get(api::RESTParams, endpoint::AbstractString, symbols=Union{<:AbstractString, <:AbstractVector{<:AbstractString}}; endpoint_base::AbstractString="stocks", kwargs...)

    page_token = nothing

    data = NamedTuple(kwargs)

    limit = get(data, :limit, nothing)

    if isa(symbols, AbstractString)
        path = "/$(endpoint_base)/$(symbols)/$(endpoint)"
    else
        path = "/$(endpoint_base)/$(endpoint)"
        (first_symbol, other_symbols) = Iterators.peel(symbols)
        symbol_str = first_symbol
        for symbol in other_symbols
            symbol_str = symbol_str * "," * symbol
        end
        data = merge(data, (symbols=symbol_str,))
    end

    return Channel() do c
        while true
            if limit !== nothing
                actual_limit = min(limit - total_items, DATA_V2_MAX_LIMIT)
                if actual_limit < 1
                    break
                end
            else
                actual_limit = nothing
            end

            this_data = merge(data, (page_token=page_token,))
            if actual_limit !== nothing
                this_data = merge(this_data, (limit=actual_limit,))
            end

            res = _request(api, "GET", path, this_data; base_url=api.data_url)

            if isa(symbols, AbstractString)
                for item in get(res, String(endpoint), [])
                    item["symbol"] = String(symbols)
                    push!(c, item)
                end
            else
                by_symbol = get(res, String(endpoint), Dict())
                for sym in sort(keys(by_symbol))
                    items = by_symbol[sym]
                    for item in items
                        item["symbol"] = String(sym)
                        push!(c, item)
                    end
                end
            end

            page_token = res["next_page_token"]

            if page_token === nothing
                break
            end
        end
    end

end

function get_bars(
        api::RESTParams,
        symbol::Union{<:AbstractString, <:AbstractVector{<:AbstractString}},
        timeframe::TimeFrame;
        start::Maybe{<:DateTime}=nothing,
        stop::Maybe{<:DateTime}=nothing,
        adjustment::String="raw",
        limit::Maybe{<:Integer}=nothing
    )

    bars_generator  = _data_get(
        api,
        "bars",
        symbol;
        timeframe=timeframe,
        adjustment=adjustment,
        start=start,
        stop=stop,
        limit=limit
    )

    return (wrap_response(Bar, bar) for bar in bars_generator)
end

function get_latest_bar(api::RESTParams, symbol::String)

    res = _request(api, "GET", "/stocks/$(symbol)/bars/latest"; base_url=api.data_url)

    bar = res["bar"]
    bar["symbol"] = symbol
    return wrap_response(Bar, bar)
end
