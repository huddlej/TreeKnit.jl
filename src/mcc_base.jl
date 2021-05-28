"""
    naive_mccs(treelist)

Find sets of nodes which are:
- clades in all trees of `treelist`,
- all subclades of nodes are clades in all trees of `treelist` (both of these properties define consistency),
- maximal: adding a node to a set results it in not being a clade in at least one of the trees.
All the trees of `treelist` should share the same leaf nodes.
"""
function naive_mccs(treelist)

    # Checking that trees have the same label for leaf nodes
    sh = mapreduce(t->share_labels(t[1],t[2]), *, zip(treelist[1:end-1], treelist[2:end]))
    !sh && error("Can only be used on trees that share leaf nodes.")

    # List of splits in trees
    S = Tuple(SplitList(t) for t in treelist)

    # List of already visited nodes
    tref = treelist[1]
    checklist = Dict(k=>false for k in keys(tref.lleaves))

    # Explore one leaf at a time
    mc_clades = []
    for (cl,v) in checklist
        if !v # If leave not already visited
            # We're going to go up in all trees at the same time
            croot = [t.lleaves[cl] for t in treelist] # Root of current maximal clade, in all trees
            clabel = [cl]
            # Initial individual, always a common clade in all trees since it's a leaf.
            flag = true
            while flag && prod(!x.isroot for x in croot)
                nroot = [x.anc for x in croot] # Ancestors of current maximal clade in all trees
                # Each element of `nroot` defines a new set of labels corresponding to one tree. There are two possibilites
                # (i) Those sets of labels match. In this case, we have a potential consistent clade. To check further, call `is_coherent_clade`.
                # (ii) Otherwise, the topology of trees in `treelist` is inconsistent above `croot`. `croot` is an MCC, break.
                if mapreduce(i->S[1].splitmap[nroot[1].label] == S[i].splitmap[nroot[i].label], *, 2:length(nroot))
                    # --> `r \in nroot` is the same split in all trees
                    if is_coherent_clade(nroot,S) # check if children of `r` are also same splits in all trees
                        if nroot == croot # Singleton in the tree, or clade with a single node --> the algorithm is getting stuck on this node
                            croot = [x.anc for x in croot]
                        else
                            croot = nroot
                        end
                        clabel = S[1].leaves[S[1].splitmap[nroot[1].label].dat]
                    else
                        flag = false
                    end
                else
                    flag = false
                end
            end
            #
            map(x->checklist[x]=true, [c for c in clabel])
            push!(mc_clades, sort([c for c in clabel]))
        end
    end
    return sort(mc_clades, lt = clt)
end
naive_mccs(t...) = naive_mccs(collect(t))

#= Custom order for MCCs =#
function clt(x,y)
    if length(x) < length(y)
        return true
    elseif length(x) > length(y)
        return false
    else
        return x[1] < y[1]
    end
end
function sort_mccs(mccs)
    return sort([sort(x) for x in mccs], lt=clt)
end



"""
    is_coherent_clade(r::TreeNode, S::Tuple{SplitList})

Do all children of `r` correspond to the same splits?

In practice, check that the splits `S[i].splitmap[c]` for `i` in `1:length(S)` and `c` in children of `r` are all the same.
"""
function is_coherent_clade(roots::Array{<:TreeNode,1}, S::Tuple{<:SplitList,n} where n)
    #
    if length(roots) != length(S)
        @error "`roots` and `S` do not have the same length."
    end

    # All `r` in `roots` should at least have the same number of children
    if !mapreduce(ic-> length(roots[ic].child) == length(roots[1].child), *, 2:length(roots))
        return false
    end

    # Checking clade consistency
    for cref in roots[1].child
        if cref.isleaf
            for i in 2:length(roots)
                found = false
                for c in roots[i].child
                    if c.label == cref.label
                        found = true
                        break
                    end
                end
                if !found
                    return false
                end
            end
        else
            children = [cref]
            sref = S[1].splitmap[cref.label]
            # Looking at child `cref` for `roots[1]`
            # For every `r` in roots, there has to be a child `c` with the same split
            for i in 2:length(roots)
                for c in roots[i].child
                    if !c.isleaf && S[i].splitmap[c.label] == sref
                        push!(children, c)
                        break
                    end
                end
                if length(children) != i # nothing found
                    return false
                end
            end

            # Clade below all children found
            if !is_coherent_clade(children, S)
                return false
            end
        end
    end
    return true
end

"""
    name_mcc_clades!(treelist, MCC)

For each clade `m` in `MCC`:
- Rename the root `r` of `m` to `MCC_\$(i)` or (`\$(r.label)` if `r` is a leaf) where `i` is an integer starting at `label_init`.
- Rename each non-leaf internal node of `m` to `shared_\$i_\$j` where `j` is an index specific to `m`.

## Procedure
In an MCC internal node is defined in all trees by the clade it forms.
"""
function name_mcc_clades!(treelist, MCC)
    # Finding initial label
    label_init = 1
    for t in treelist
        for n in values(t.lnodes)
            if match(r"MCC", n.label)!=nothing && parse(Int64, n.label[5:end]) >= label_init
                label_init = parse(Int64, n.label[5:end]) + 1
            end
        end
    end

    nd = Dict()
    for (i,m) in enumerate(MCC)
        cl = i + label_init - 1
        # Renaming root
        for t in treelist
            r = lca([t.lnodes[x] for x in m])
            old_label = r.label
            new_label = r.isleaf ? "$(old_label)" : "MCC_$(cl)"
            r.label = new_label
            delete!(t.lnodes, old_label)
            t.lnodes[new_label] = r
            nd[new_label] = m
        end

        # Renaming internal nodes - Using the first element of treelist to iterate through internal nodes
        r1 = lca([treelist[1].lnodes[x] for x in m])
        j = 1
        for n in TreeTools.POT(r1)
            if n!=r1 && !n.isleaf
                # Relevant internal node. Rename it in all trees
                # `llist` acts as a common identifier for `n` in all trees
                llist = [x.label for x in TreeTools.POTleaves(n)]
                for t in treelist
                    ln = lca([t.lnodes[x] for x in llist])
                    old_label = ln.label
                    new_label = "shared_$(cl)_$j"
                    ln.label = new_label
                    delete!(t.lnodes, old_label)
                    t.lnodes[new_label] = ln
                end
                j += 1
            end
        end
    end
    return nd
end



"""
    reduce_to_mcc(tree, MCC)

Reduce `tree` to its MCC by grouping leaves. Returns a tree with `length(MCC)` leaves.
"""
function reduce_to_mcc(tree::Tree, MCC)
    out = copy(tree)
    reduce_to_mcc!(out, MCC)
    return out
end
"""
    reduce_to_mcc!(tree, MCC)

Reduce `tree` to `MCCs` by grouping leaves.
"""
function reduce_to_mcc!(tree::Tree, MCC)
    for m in MCC
        r = lca([tree.lnodes[x] for x in m])
        if r.isroot
            node2tree!(tree, TreeNode(r.data, isleaf=true, isroot = true, label=r.label))
        elseif !r.isleaf
            rn = TreeNode(r.data, isleaf=true, isroot = true, label=r.label)
            a = r.anc
            prunenode!(r)
            graftnode!(a, rn)
        end
    end
    node2tree!(tree, tree.root)
end

