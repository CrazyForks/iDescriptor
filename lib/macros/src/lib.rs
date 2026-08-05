// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use proc_macro::TokenStream;
use quote::quote;
use syn::{DeriveInput, parse_macro_input};

#[proc_macro_derive(QtThreading)]
pub fn derive_qt_threading(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);

    let name = input.ident;
    let generics = input.generics;
    let (impl_generics, ty_generics, where_clause) = generics.split_for_impl();

    let expanded = quote! {
        impl #impl_generics crate::qt_threading::QtThreading for #name #ty_generics #where_clause {
            fn qt_thread(&self) -> crate::qt_threading::QtThread<Self>
            where
                Self: Sized,
            {
                crate::qt_threading::QtThread::new(self)
            }
        }
    };

    TokenStream::from(expanded)
}
