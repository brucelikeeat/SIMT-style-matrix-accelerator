// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vgpu_top_tb.h for the primary calling header

#include "Vgpu_top_tb__pch.h"

void Vgpu_top_tb___024root___ctor_var_reset(Vgpu_top_tb___024root* vlSelf);

Vgpu_top_tb___024root::Vgpu_top_tb___024root(Vgpu_top_tb__Syms* symsp, const char* namep)
    : __VdlySched{*symsp->_vm_contextp__}
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    Vgpu_top_tb___024root___ctor_var_reset(this);
}

void Vgpu_top_tb___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vgpu_top_tb___024root::~Vgpu_top_tb___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
