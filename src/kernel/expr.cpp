/*
Copyright (c) 2013 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Author: Leonardo de Moura
        Soonho Kong
*/
#include <vector>
#include <sstream>
#include "expr.h"
#include "sets.h"
#include "hash.h"
#include "format.h"

namespace lean {

unsigned hash_args(unsigned size, expr const * args) {
    return hash(size, [&args](unsigned i){ return args[i].hash(); });
}

expr_cell::expr_cell(expr_kind k, unsigned h):
    m_kind(static_cast<unsigned>(k)),
    m_flags(0),
    m_hash(h),
    m_rc(1) {}

expr_var::expr_var(unsigned idx):
    expr_cell(expr_kind::Var, idx),
    m_vidx(idx) {}

expr_const::expr_const(name const & n, unsigned pos):
    expr_cell(expr_kind::Constant, n.hash()),
    m_name(n),
    m_pos(pos) {}

expr_app::expr_app(unsigned num_args):
    expr_cell(expr_kind::App, 0),
    m_num_args(num_args) {
}
expr_app::~expr_app() {
    for (unsigned i = 0; i < m_num_args; i++)
        (m_args+i)->~expr();
}
expr app(unsigned n, expr const * as) {
    lean_assert(n > 1);
    unsigned new_n;
    unsigned n0 = 0;
    expr const & arg0 = as[0];
    // Remark: we represent ((app a b) c) as (app a b c)
    if (is_app(arg0)) {
        n0    = num_args(arg0);
        new_n = n + n0 - 1;
    }
    else {
        new_n = n;
    }
    char * mem   = new char[sizeof(expr_app) + new_n*sizeof(expr)];
    expr r(new (mem) expr_app(new_n));
    expr * m_args = to_app(r)->m_args;
    unsigned i = 0;
    unsigned j = 0;
    if (new_n != n) {
        for (; i < n0; i++)
            new (m_args+i) expr(arg(arg0, i));
        j++;
    }
    for (; i < new_n; ++i, ++j) {
        lean_assert(j < n);
        new (m_args+i) expr(as[j]);
    }
    to_app(r)->m_hash = hash_args(new_n, m_args);
    return r;
}

expr_abstraction::expr_abstraction(expr_kind k, name const & n, expr const & t, expr const & b):
    expr_cell(k, ::lean::hash(t.hash(), b.hash())),
    m_name(n),
    m_type(t),
    m_body(b) {
}
expr_lambda::expr_lambda(name const & n, expr const & t, expr const & e):
    expr_abstraction(expr_kind::Lambda, n, t, e) {}
expr_pi::expr_pi(name const & n, expr const & t, expr const & e):
    expr_abstraction(expr_kind::Pi, n, t, e) {}

expr_type::expr_type(level const & l):
    expr_cell(expr_kind::Type, l.hash()),
    m_level(l) {
}
expr_type::~expr_type() {
}
expr_numeral::expr_numeral(mpz const & n):
    expr_cell(expr_kind::Numeral, n.hash()),
    m_numeral(n) {}

void expr_cell::dealloc() {
    switch (kind()) {
    case expr_kind::Var:        delete static_cast<expr_var*>(this); break;
    case expr_kind::Constant:   delete static_cast<expr_const*>(this); break;
    case expr_kind::App:        static_cast<expr_app*>(this)->~expr_app(); delete[] reinterpret_cast<char*>(this); break;
    case expr_kind::Lambda:     delete static_cast<expr_lambda*>(this); break;
    case expr_kind::Pi:         delete static_cast<expr_pi*>(this); break;
    case expr_kind::Type:       delete static_cast<expr_type*>(this); break;
    case expr_kind::Numeral:    delete static_cast<expr_numeral*>(this); break;
    }
}

class eq_fn {
    expr_cell_pair_set m_eq_visited;

    bool apply(expr const & a, expr const & b) {
        if (eqp(a, b))            return true;
        if (a.hash() != b.hash()) return false;
        if (a.kind() != b.kind()) return false;
        if (is_var(a))            return var_idx(a) == var_idx(b);
        if (is_shared(a) && is_shared(b)) {
            auto p = std::make_pair(a.raw(), b.raw());
            if (m_eq_visited.find(p) != m_eq_visited.end())
                return true;
            m_eq_visited.insert(p);
        }
        switch (a.kind()) {
        case expr_kind::Var:      lean_unreachable(); return true;
        case expr_kind::Constant: return const_name(a) == const_name(b);
        case expr_kind::App:
            if (num_args(a) != num_args(b))
                return false;
            for (unsigned i = 0; i < num_args(a); i++)
                if (!apply(arg(a, i), arg(b, i)))
                    return false;
            return true;
        case expr_kind::Lambda:
        case expr_kind::Pi:
            // Lambda and Pi
            // Remark: we ignore get_abs_name because we want alpha-equivalence
            return apply(abst_type(a), abst_type(b)) && apply(abst_body(a), abst_body(b));
        case expr_kind::Type:     return ty_level(a) == ty_level(b);
        case expr_kind::Numeral:  return num_value(a) == num_value(b);
        }
        lean_unreachable();
        return false;
    }
public:
    bool operator()(expr const & a, expr const & b) {
        return apply(a, b);
    }
};

bool operator==(expr const & a, expr const & b) {
    return eq_fn()(a, b);
}

// Low-level pretty printer
std::ostream & operator<<(std::ostream & out, expr const & a) {
    switch (a.kind()) {
    case expr_kind::Var:      out << "#" << var_idx(a); break;
    case expr_kind::Constant: out << const_name(a);     break;
    case expr_kind::App:
        out << "(";
        for (unsigned i = 0; i < num_args(a); i++) {
            if (i > 0) out << " ";
            out << arg(a, i);
        }
        out << ")";
        break;
    case expr_kind::Lambda:  out << "(fun (" << abst_name(a) << " : " << abst_type(a) << ") " << abst_body(a) << ")";    break;
    case expr_kind::Pi:      out << "(pi (" << abst_name(a) << " : " << abst_type(a) << ") " << abst_body(a) << ")"; break;
    case expr_kind::Type:    out << "(Type " << ty_level(a) << ")"; break;
    case expr_kind::Numeral: out << num_value(a); break;
    }
    return out;
}

expr copy(expr const & a) {
    switch (a.kind()) {
    case expr_kind::Var:      return var(var_idx(a));
    case expr_kind::Constant: return constant(const_name(a), const_pos(a));
    case expr_kind::Type:     return type(ty_level(a));
    case expr_kind::Numeral:  return numeral(num_value(a));
    case expr_kind::App:      return app(num_args(a), begin_args(a));
    case expr_kind::Lambda:   return lambda(abst_name(a), abst_type(a), abst_body(a));
    case expr_kind::Pi:       return pi(abst_name(a), abst_type(a), abst_body(a));
    }
    lean_unreachable();
    return expr();
}
}

lean::format pp_aux(lean::expr const & a) {
    using namespace lean;
    switch (a.kind()) {
    case expr_kind::Var:
        return format{format("#"), format(static_cast<int>(var_idx(a)))};
    case expr_kind::Constant:
        return format(const_name(a));
    case expr_kind::App:
    {
        format r;
        for (unsigned i = 0; i < num_args(a); i++) {
            if (i > 0) r += format(" ");
            r += pp_aux(arg(a, i));
        }
        return paren(r);
    }
    case expr_kind::Lambda:
        return paren(format{
                       highlight(format("\u03BB "), format::format_color::PINK), /* Use unicode lambda */
                       paren(format{
                               format(abst_name(a)),
                               format(" : "),
                               pp_aux(abst_type(a))}),
                       format(" "),
                       pp_aux(abst_body(a))});
    case expr_kind::Pi:
        return paren(format{
                       highlight(format("\u03A0 "), format::format_color::ORANGE), /* Use unicode lambda */
                       paren(format{
                               format(abst_name(a)),
                               format(" : "),
                               pp_aux(abst_type(a))}),
                       format(" "),
                       pp_aux(abst_body(a))});
    case expr_kind::Type:
    {
        std::stringstream ss;
        ss << ty_level(a);

        return paren(format{format("Type "),
                            format(ss.str())});
    }
    case expr_kind::Numeral:
        return format(num_value(a));
    }
    lean_unreachable();
    return format();
}

void pp(lean::expr const & a) {
    lean::format const & f = pp_aux(a);
    std::cout << f;
}
