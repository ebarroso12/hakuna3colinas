import 'package:flutter/material.dart';

/// Campo de senha com botão de olho pra mostrar/esconder o que foi digitado.
///
/// Usa `TextFormField` e não `TextField`: assim ele participa da validação
/// do `Form` que o envolve. Sem isso, a tela de cadastro validaria nome e
/// telefone mas deixaria a senha passar sem conferir tamanho — e o erro só
/// apareceria no servidor, depois da ficha inteira preenchida.
///
/// Fora de um `Form` continua funcionando igual, então as telas que só
/// passam `controller` e `labelText` não mudam.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.validator,
    this.comBorda = false,
  });

  final TextEditingController controller;
  final String labelText;

  /// Opcional. Quando dado, o campo entra na validação do `Form`.
  final String? Function(String?)? validator;

  /// Desenha a borda externa, para combinar com formulários que usam
  /// `OutlineInputBorder`. Falso mantém o visual das telas antigas.
  final bool comBorda;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      // Valida enquanto digita DEPOIS do primeiro erro. Senão, quem erra a
      // repetição da senha só descobre ao apertar o botão de novo.
      autovalidateMode: widget.validator == null
          ? AutovalidateMode.disabled
          : AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.labelText,
        border: widget.comBorda ? const OutlineInputBorder() : null,
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
