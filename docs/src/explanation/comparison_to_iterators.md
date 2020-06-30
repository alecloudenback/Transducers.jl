# [Comparison to iterators](@id comparison-to-iterators)

```@meta
DocTestSetup = quote
    using Transducers
end
```

How `foldl` is used illustrates the difference between iterators and
transducers.  Consider a transducer

```jldoctest filter-map
julia> using Transducers

julia> xf = Filter(iseven) |> Map(x -> 2x);
```

which works as

```jldoctest filter-map
julia> collect(xf, 1:6)
3-element Array{Int64,1}:
  4
  8
 12

julia> foldl(+, xf, 1:6)  # 4 + 8 + 12
24
```

Implementation of the above computation in iterator would be:

```julia
f(x) = 2x
imap = Base.Iterators.Generator  # like `map`, but returns an iterator
mapfoldl(f, +, filter(iseven, input), init=0)
foldl(+, imap(f, filter(iseven, input)))  # equivalent
#        ______________________________
#        composition occurs at input part
```

Compare it to how transducers are used:

```julia
foldl(+, Filter(iseven) |> Map(f), input, init=0)
#        ________________________
#        composition occurs at computation part
```

Although this is just a syntactic difference, it is reflected in the
actual code generated by those two frameworks.  The code for iterator
would be lowered to:

```jldoctest manual-composition; output = false
function map_filter_iterators(xs, init)
    ret = iterate(xs)
    ret === nothing && return init
    acc = init
    @goto filter
    local state, x
    while true
        while true                                    # input
            ret = iterate(xs, state)                  #
            ret === nothing && return acc             #
            @label filter                             #
            x, state = ret                            #
            iseven(x) && break             # filter   :
        end                                #          :
        y = 2x              # imap         :          :
        acc += y    # +     :              :          :
    end             # :     :              :          :
    #                 + <-- imap <-------- filter <-- input
end

# output

map_filter_iterators (generic function with 1 method)
```

Notice that the iteration of `input` is the _inner_ most block,
followed by `filter`, `imap`, and then finally `+`.  Iterators are
described as _pull-based_; an outer iterator (say `imap`) has to
"pull" an item from the inner iterator (`filter` in above example).
It is reflected in the lowered code above.

On the other hand, the code using transducers is lowered to:

```jldoctest manual-composition; output = false
function map_filter_transducers(xs, init)
    acc = init
    #              input -> Filter --> Map --> +
    for x in xs  # input    :          :       :
        if iseven(x)  #     Filter     :       :
            y = 2x    #                Map     :
            acc += y  #                        +
        end
    end
    return acc
end

xs = [6, 8, 1, 4, 5, 6, 6, 7, 9, 9, 7, 8, 6, 8, 2, 5, 2, 4, 3, 7]
@assert map_filter_iterators(xs, 0) == map_filter_transducers(xs, 0)

# output

```

Notice that the iteration of `input` is at the _outer_ most block
while `+` is in the inner most block.  Transducers passed to
`foldl` appears in the block between them in the order they are
composed.  An outer transducer (say `Filter`) "pushes" _arbitrary_
number of items to the inner transducer (`Map` in above example).
Note that `Filter` can choose to _not_ push an item (i.e., push zero
item) when the predicate returns `false`.  This _push-based_ nature of
the transducers allows the generation of very natural and efficient
code.  To put it another way, the transducers and
[transducible processes](@ref Glossary) _own_ the loop.

As a consequence, computations requiring to expand an item into a
sequence can be processed efficiently.  Consider the following
example:

```jldoctest map-filter-cat
julia> xf = Map(x -> 1:x) |> Filter(iseven ∘ sum) |> Cat()
       foldl(*, xf, 1:10)
29262643200
```

This is lowered to a nested `for` loops:

```jldoctest map-filter-cat; output = false
function map_filter_cat_transducers(xs, init)
    acc = init
    for x in xs
        y1 = 1:x                # Map
        if iseven(sum(y1))      # Filter
            for y2 in y1        # Cat
                acc *= y2       # *
            end
        end
    end
    return acc
end

@assert foldl(*, xf, 1:10) == map_filter_cat_transducers(1:10, 1)
# output

```

It is not straightforward to implement an iterator like `Cat` that can
output more than one items at a time.  Such an iterator has to track
the state of the inner (`y1` in above) and outer (`xs` in above)
iterators and conditionally invoke the outer iterator once the inner
iterator terminates.  This generates a complicated code and the
compiler would have hard time optimizing it.

```@meta
DocTestSetup = nothing
```