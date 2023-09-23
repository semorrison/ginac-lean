#include <lean/lean.h>
#include <iostream>
#include <ginac/ginac.h>
#include "CppClass.h"
using namespace std;
using namespace GiNaC;

extern "C" uint32_t my_add(uint32_t a, uint32_t b) {
    return a + b;
}

extern "C" lean_obj_res my_lean_fun() {
    symbol x("x"), y("y"), z("z");
    ex MyEx1 = 5;                       // simple number
    ex MyEx2 = x + 2*y;                 // polynomial in x and y
    ex MyEx3 = (x + 1)/(x - 1);         // rational expression
    ex MyEx4 = sin(x + 2*y) + 3*z + 41; // containing a function
    ex MyEx5 = MyEx4 + 1;               // similar to above

    cout << MyEx5 << endl;

    return lean_io_result_mk_ok(lean_box(0));
}

extern "C" LEAN_EXPORT lean_obj_res GiNaC_symbol(b_lean_obj_arg name) {
    auto sym = new symbol(lean_string_cstr(name));
    return of_cppClass(sym);
}

extern "C" LEAN_EXPORT lean_obj_res GiNaC_symbol_name(b_lean_obj_arg _sym) {
    auto sym = to_cppClass<symbol>(_sym);
    return lean_mk_string(sym->get_name().c_str());
}
