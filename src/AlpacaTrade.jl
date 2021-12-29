module AlpacaTrade

using Base: UUID, String
using HTTP
using JSON
using Dates

const Maybe{T} = Union{Nothing, T}

include("entity.jl")
include("rest.jl")



end # module
