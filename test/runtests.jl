using Compat
using Dates
using Test

@test isempty(detect_ambiguities(Base, Core, Compat))

begin
    # A custom linear slow sparse-like array that relies upon Dict for its storage
    struct TSlow{T,N} <: AbstractArray{T,N}
        data::Dict{NTuple{N,Int}, T}
        dims::NTuple{N,Int}
    end
    TSlow(::Type{T}, dims::Int...) where {T} = TSlow(T, dims)
    TSlow(::Type{T}, dims::NTuple{N,Int}) where {T,N} = TSlow{T,N}(Dict{NTuple{N,Int}, T}(), dims)

    TSlow{T,N}(X::TSlow{T,N})         where {T,N  } = X
    TSlow(     X::AbstractArray{T,N}) where {T,N  } = TSlow{T,N}(X)
    TSlow{T  }(X::AbstractArray{_,N}) where {T,N,_} = TSlow{T,N}(X)
    TSlow{T,N}(X::AbstractArray     ) where {T,N  } = begin
        A = TSlow(T, size(X))
        for I in CartesianIndices(X)
            A[Tuple(I)...] = X[Tuple(I)...]
        end
        A
    end
    Base.size(A::TSlow) = A.dims
    Base.similar(A::TSlow, ::Type{T}, dims::Dims) where {T} = TSlow(T, dims)
    Base.IndexStyle(::Type{A}) where {A<:TSlow} = IndexCartesian()
    Base.getindex(A::TSlow{T,N}, i::Vararg{Int,N}) where {T,N} = get(A.data, i, zero(T))
    Base.setindex!(A::TSlow{T,N}, v, i::Vararg{Int,N}) where {T,N} = (A.data[i] = v)
end

# https://github.com/JuliaLang/julia/pull/35316
# https://github.com/JuliaLang/julia/pull/41076
@testset "2arg" begin
    @testset "findmin(f, domain)" begin
        @test findmin(-, 1:10) == (-10, 10)
        @test findmin(identity, [1, 2, 3, missing]) === (missing, 4)
        @test findmin(identity, [1, NaN, 3, missing]) === (missing, 4)
        @test findmin(identity, [1, missing, NaN, 3]) === (missing, 2)
        @test findmin(identity, [1, NaN, 3]) === (NaN, 2)
        @test findmin(identity, [1, 3, NaN]) === (NaN, 3)
        @test all(findmin(cos, 0:π/2:2π) .≈ (-1.0, 3))
    end

    @testset "findmax(f, domain)" begin
        @test findmax(-, 1:10) == (-1, 1)
        @test findmax(identity, [1, 2, 3, missing]) === (missing, 4)
        @test findmax(identity, [1, NaN, 3, missing]) === (missing, 4)
        @test findmax(identity, [1, missing, NaN, 3]) === (missing, 2)
        @test findmax(identity, [1, NaN, 3]) === (NaN, 2)
        @test findmax(identity, [1, 3, NaN]) === (NaN, 3)
        @test findmax(cos, 0:π/2:2π) == (1.0, 1)
    end

    @testset "argmin(f, domain)" begin
        @test argmin(-, 1:10) == 10
        @test argmin(sum, Iterators.product(1:5, 1:5)) == (1, 1)
    end

    @testset "argmax(f, domain)" begin
        @test argmax(-, 1:10) == 1
        @test argmax(sum, Iterators.product(1:5, 1:5)) == (5, 5)
    end
end

# https://github.com/JuliaLang/julia/pull/40729
@testset "@something" begin
    @test_throws ArgumentError @something()
    @test_throws ArgumentError @something(nothing)
    @test @something(1) === 1
    @test @something(Some(nothing)) === nothing

    @test @something(1, error("failed")) === 1
    @test_throws ErrorException @something(nothing, error("failed"))
end

@testset "@coalesce" begin
    @test @coalesce() === missing
    @test @coalesce(1) === 1
    @test @coalesce(nothing) === nothing
    @test @coalesce(missing) === missing

    @test @coalesce(1, error("failed")) === 1
    @test_throws ErrorException @coalesce(missing, error("failed"))
end

@testset "get" begin
     A = reshape([1:24...], 4, 3, 2)
     B = reshape([1:24...], 4, 3, 2)

     global c = 0
     f() = (global c = c+1; 0)
     @test get(f, A, ()) == 0
     @test c == 1
     @test get(f, B, ()) == 0
     @test c == 2
     @test get(f, A, (1,)) == get(f, A, 1) == A[1] == 1
     @test c == 2
     @test get(f, B, (1,)) == get(f, B, 1) == B[1] == 1
     @test c == 2
     @test get(f, A, (25,)) == get(f, A, 25) == 0
     @test c == 4
     @test get(f, B, (25,)) == get(f, B, 25) == 0
     @test c == 6
     @test get(f, A, (1,1,1)) == A[1,1,1] == 1
     @test get(f, B, (1,1,1)) == B[1,1,1] == 1
     @test get(f, A, (1,1,3)) == 0
     @test c == 7
     @test get(f, B, (1,1,3)) == 0
     @test c == 8
     @test get(f, TSlow([]), ()) == 0
     @test c == 9

     @test get((5, 6, 7), 1, 0) == 5
     @test get((), 5, 0) == 0
     @test get((1,), 3, 0) == 0
     @test get(()->0, (5, 6, 7), 1) == 5
     @test get(()->0, (), 4) == 0
     @test get(()->0, (1,), 3) == 0

    for x in [1.23, 7, ℯ, 4//5] #[FP, Int, Irrational, Rat]
         @test get(x, 1, 99) == x
         @test get(x, (), 99) == x
         @test get(x, (1,), 99) == x
         @test get(x, 2, 99) == 99
         @test get(x, 0, pi) == pi
         @test get(x, (1,2), pi) == pi
         c = Ref(0)
         @test get(() -> c[]+=1, x, 1) == x
         @test get(() -> c[]+=1, x, ()) == x
         @test get(() -> c[]+=1, x, (1,1,1)) == x
         @test get(() -> c[]+=1, x, 2) == 1
         @test get(() -> c[]+=1, x, -1) == 2
         @test get(() -> c[]+=1, x, (3,2,1)) == 3
    end
end

# https://github.com/JuliaLang/julia/pull/39285
struct X
    x
end
@testset "property destructuring assignment" begin
    nt = (; a=1, b=2, c=3)
    @compat (; c, b) = nt
    @test c == nt.c
    @test b == nt.b

    @compat (; x) = X(1)
    @test x == 1
end

# https://github.com/JuliaLang/julia/pull/29901
@testset "current_exceptions" begin
    # Helper method to retrieve an ExceptionStack that should contain two exceptions,
    # each of which accompanied by a backtrace or `nothing` according to `with_backtraces`.
    function _retrieve_exception_stack(;with_backtraces::Bool)
        exception_stack = try
            try
                # Generate the first exception:
                __not_a_binding__
            catch
                # Catch the first exception, and generate a second exception
                # during what would be handling of the first exception:
                1 ÷ 0
            end
        catch
            # Retrieve an ExceptionStack with both exceptions,
            # and bind `exception_stack` (at the top of this block) thereto:
            current_exceptions(;backtrace=with_backtraces)
        end
        return exception_stack
    end

    excs_with_bts = _retrieve_exception_stack(with_backtraces = true)
    excs_sans_bts = _retrieve_exception_stack(with_backtraces = false)

    # Check that the ExceptionStack with backtraces contains backtraces:
    BACKTRACE_TYPE = Vector{Union{Ptr{Nothing}, Base.InterpreterIP}}
    @test all(exc_with_bt[2] isa BACKTRACE_TYPE for exc_with_bt in excs_with_bts)

    # Check that the ExceptionStack without backtraces contains `nothing`s:
    @test all(exc_sans_bt[2] isa Nothing for exc_sans_bt in excs_sans_bts)

    # Check that the ExceptionStacks contain the expected exception types:
    @test typeof.(first.(excs_with_bts)) == [UndefVarError, DivideError]
    @test typeof.(first.(excs_sans_bts)) == [UndefVarError, DivideError]

    # Check that the ExceptionStack with backtraces `show`s correctly:
    @test occursin(r"""
    2-element ExceptionStack:
    DivideError: integer division error
    Stacktrace:.*

    caused by: UndefVarError: __not_a_binding__ not defined
    Stacktrace:.*
    """s, sprint(show, excs_with_bts))

    # Check that the ExceptionStack without backtraces `show`s correctly:
    @test occursin(r"""
    2-element ExceptionStack:
    DivideError: integer division error

    caused by: UndefVarError: __not_a_binding__ not defined"""s,
    sprint(show, excs_sans_bts))

    # Check that the ExceptionStack with backtraces `display_error`s correctly:
    @test occursin(r"""
    ERROR: DivideError: integer division error
    Stacktrace:.*

    caused by: UndefVarError: __not_a_binding__ not defined
    Stacktrace:.*
    """s, sprint(Base.display_error, excs_with_bts))

    # Check that the ExceptionStack without backtraces `display_error`s correctly:
    @test occursin(r"""
    ERROR: DivideError: integer division error

    caused by: UndefVarError: __not_a_binding__ not defined"""s,
    sprint(Base.display_error, excs_sans_bts))
end

# https://github.com/JuliaLang/julia/pull/39794
@testset "Returns" begin
    @test @inferred(Returns(1)()   ) === 1
    @test @inferred(Returns(1)(23) ) === 1
    @test @inferred(Returns("a")(2,3)) == "a"
    @test @inferred(Returns(1)(x=1, y=2)) === 1
    @test @inferred(Returns(Int)()) === Int
    @test @inferred(Returns(Returns(1))()) === Returns(1)
    f = @inferred Returns(Int)
    @inferred f(1,2)
    val = [1,2,3]
    @test Returns(val)(1) === val
    @test sprint(show, Returns(1.0)) == "Returns{Float64}(1.0)"
end

# https://github.com/JuliaLang/julia/pull/42125
@testset "@constprop" begin
    Compat.@constprop :aggressive aggf(x) = Symbol(x)
    Compat.@constprop :none      nonef(x) = Symbol(x)
    @test_throws Exception Meta.lower(@__MODULE__,
        quote
            Compat.@constprop :other brokenf(x) = Symbol(x)
        end
    )
    @test aggf("hi") == nonef("hi") == :hi
end

# https://github.com/JuliaLang/julia/pull/41312
@testset "`@inline`/`@noinline` annotations within a function body" begin
    callf(f, args...) = f(args...)
    function foo1(a)
        Compat.@inline
        sum(sincos(a))
    end
    foo2(a) = (Compat.@inline; sum(sincos(a)))
    foo3(a) = callf(a) do a
        Compat.@inline
        sum(sincos(a))
    end
    function foo4(a)
        Compat.@noinline
        sum(sincos(a))
    end
    foo5(a) = (Compat.@noinline; sum(sincos(a)))
    foo6(a) = callf(a) do a
        Compat.@noinline
        sum(sincos(a))
    end

    @test foo1(42) == foo2(42) == foo3(42) == foo4(42) == foo5(42) == foo6(42)
end

# https://github.com/JuliaLang/julia/pull/41328
@testset "callsite annotations of inlining" begin
    function foo1(a)
        Compat.@inline begin
            return sum(sincos(a))
        end
    end
    function foo2(a)
        Compat.@noinline begin
            return sum(sincos(a))
        end
    end

    @test foo1(42) == foo2(42)
end

# https://github.com/JuliaLang/julia/pull/40803
@testset "Convert CompoundPeriod to Period" begin
    @test convert(Month, Year(1) + Month(1)) === Month(13)
    @test convert(Second, Minute(1) + Second(30)) === Second(90)
    @test convert(Minute, Minute(1) + Second(60)) === Minute(2)
    @test convert(Millisecond, Minute(1) + Second(30)) === Millisecond(90_000)
    @test_throws InexactError convert(Minute, Minute(1) + Second(30))
    @test_throws MethodError convert(Month, Minute(1) + Second(30))
    @test_throws MethodError convert(Second, Month(1) + Second(30))
    @test_throws MethodError convert(Period, Minute(1) + Second(30))
    @test_throws MethodError convert(Dates.FixedPeriod, Minute(1) + Second(30))
end

@testset "ismutabletype" begin
    @test ismutabletype(Array)
    @test !ismutabletype(Tuple)
end

# https://github.com/JuliaLang/julia/pull/39245

#=
cmcaine commented on Sep 8, 2021

This PR implements split with eachsplit and uses eachsplit in a few other places in Base, 
so it's kind of already covered by the existing tests. 
Not sure it needs any more?

so, these are the Base.split tests, but replacing split with eachsplit |> collect
=#
@testset "eachsplit" begin
    @test eachsplit("foo,bar,baz", 'x') |> collect == ["foo,bar,baz"]
    @test eachsplit("foo,bar,baz", ',') |> collect == ["foo","bar","baz"]
    @test eachsplit("foo,bar,baz", ",") |> collect == ["foo","bar","baz"]
    @test eachsplit("foo,bar,baz", r",") |> collect == ["foo","bar","baz"]
    @test eachsplit("foo,bar,baz", ','; limit=0) |> collect == ["foo","bar","baz"]
    @test eachsplit("foo,bar,baz", ','; limit=1) |> collect == ["foo,bar,baz"]
    @test eachsplit("foo,bar,baz", ','; limit=2) |> collect == ["foo","bar,baz"]
    @test eachsplit("foo,bar,baz", ','; limit=3) |> collect == ["foo","bar","baz"]
    @test eachsplit("foo,bar", "o,b") |> collect == ["fo","ar"]

    @test eachsplit("", ',') |> collect == [""]
    @test eachsplit(",", ',') |> collect == ["",""]
    @test eachsplit(",,", ',') |> collect == ["","",""]
    @test eachsplit("", ','  ; keepempty=false) |> collect == SubString[]
    @test eachsplit(",", ',' ; keepempty=false) |> collect == SubString[]
    @test eachsplit(",,", ','; keepempty=false) |> collect == SubString[]

    @test eachsplit("a b c") |> collect == ["a","b","c"]
    @test eachsplit("a  b \t c\n") |> collect == ["a","b","c"]
    @test eachsplit("α  β \u2009 γ\n") |> collect == ["α","β","γ"]

    @test eachsplit("a b c"; limit=2) |> collect == ["a","b c"]
    @test eachsplit("a  b \t c\n"; limit=3) |> collect == ["a","b","\t c\n"]
    @test eachsplit("a b c"; keepempty=true) |> collect == ["a","b","c"]
    @test eachsplit("a  b \t c\n"; keepempty=true) |> collect == ["a","","b","","","c",""]

    let str = "a.:.ba..:..cba.:.:.dcba.:."
        @test eachsplit(str, ".:.") |> collect == ["a","ba.",".cba",":.dcba",""]
        @test eachsplit(str, ".:."; keepempty=false) |> collect == ["a","ba.",".cba",":.dcba"]
        @test eachsplit(str, ".:.") |> collect == ["a","ba.",".cba",":.dcba",""]
        @test eachsplit(str, r"\.(:\.)+") |> collect == ["a","ba.",".cba","dcba",""]
        @test eachsplit(str, r"\.(:\.)+"; keepempty=false) |> collect == ["a","ba.",".cba","dcba"]
        @test eachsplit(str, r"\.+:\.+") |> collect == ["a","ba","cba",":.dcba",""]
        @test eachsplit(str, r"\.+:\.+"; keepempty=false) |> collect == ["a","ba","cba",":.dcba"]
    end

    # zero-width splits
    @test eachsplit("", "") |> collect == rsplit("", "") == [""]
    @test eachsplit("abc", "") |> collect == rsplit("abc", "") == ["a","b","c"]
    @test eachsplit("abc", "", limit=2)  |> collect == ["a","bc"]

    @test eachsplit("", r"")  |> collect == [""]
    @test eachsplit("abc", r"") |> collect == ["a","b","c"]
    @test eachsplit("abcd", r"b?") |> collect == ["a","c","d"]
    @test eachsplit("abcd", r"b*") |> collect == ["a","c","d"]
    @test eachsplit("abcd", r"b+") |> collect == ["a","cd"]
    @test eachsplit("abcd", r"b?c?") |> collect == ["a","d"]
    @test eachsplit("abcd", r"[bc]?") |> collect == ["a","","d"]
    @test eachsplit("abcd", r"a*") |> collect == ["","b","c","d"]
    @test eachsplit("abcd", r"a+") |> collect == ["","bcd"]
    @test eachsplit("abcd", r"d*") |> collect == ["a","b","c",""]
    @test eachsplit("abcd", r"d+") |> collect == ["abc",""]
    @test eachsplit("abcd", r"[ad]?") |> collect == ["","b","c",""]

    # multi-byte unicode characters (issue #26225)
    @test eachsplit("α β γ", " ") |> collect == rsplit("α β γ", " ") ==
        eachsplit("α β γ", isspace) |> collect == rsplit("α β γ", isspace) == ["α","β","γ"]
    @test eachsplit("ö.", ".") |> collect == rsplit("ö.", ".") == ["ö",""]
    @test eachsplit("α β γ", "β") |> collect == rsplit("α β γ", "β") == ["α "," γ"]
end

# https://github.com/JuliaLang/julia/pull/43354
@testset "allequal" begin
    @test allequal(Set())
    @test allequal(Set(1))
    @test !allequal(Set([1, 2]))
    @test allequal(Dict())
    @test allequal(Dict(:a => 1))
    @test !allequal(Dict(:a => 1, :b => 2))
    @test allequal([])
    @test allequal([1])
    @test allequal([1, 1])
    @test !allequal([1, 1, 2])
    @test allequal([:a, :a])
    @test !allequal([:a, :b])
    @test !allequal(1:2)
    @test allequal(1:1)
    @test !allequal(4.0:0.3:7.0)
    @test allequal(4:-1:5)       # empty range
    @test !allequal(7:-1:1)       # negative step
    @test !allequal(Date(2018, 8, 7):Day(1):Date(2018, 8, 11))  # JuliaCon 2018
    @test !allequal(DateTime(2018, 8, 7):Hour(1):DateTime(2018, 8, 11))
    @test allequal(StepRangeLen(1.0, 0.0, 2))
    @test !allequal(StepRangeLen(1.0, 1.0, 2))
    @test allequal(LinRange(1, 1, 0))
    @test allequal(LinRange(1, 1, 1))
    @test allequal(LinRange(1, 1, 2))
    @test !allequal(LinRange(1, 2, 2))
end

