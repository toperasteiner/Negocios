// lib/Pedidos/comprovante_pdf.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // intl pt_BR
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// ---- API pública -----------------------------------------------------------

class ComprovanteScreen extends StatefulWidget {
  final Uint8List bytes;
  const ComprovanteScreen({super.key, required this.bytes});

  static bool _intlReady = false;

  /// Abre a tela já gerando o PDF a partir do `pedidoId`
  static Future<void> open(BuildContext context, String pedidoId) async {
    // Mostra loader antes de qualquer trabalho
    _showBlockingLoader(context, message: 'Gerando comprovante…');

    Uint8List? bytes;
    Object? errorObj;

    try {
      // Inicializa intl (pt_BR) só 1x
      if (!_intlReady) {
        try {
          await initializeDateFormatting('pt_BR');
          Intl.defaultLocale = 'pt_BR';
        } catch (_) {}
        _intlReady = true;
      }

      // Gera PDF
      bytes = await _ComprovanteBuilder().buildForPedido(pedidoId);
    } catch (e) {
      errorObj = e;
    } finally {
      // Fecha o loader com segurança (mesmo se der erro)
      if (context.mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }

    if (errorObj != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao gerar comprovante: $errorObj')),
        );
      }
      return;
    }

    if (bytes != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ComprovanteScreen(bytes: bytes!)),
      );
    }
  }

  // Dialog de carregamento bloqueante
  static void _showBlockingLoader(BuildContext context, {String? message}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder:
          (_) => WillPopScope(
            onWillPop: () async => false,
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 64),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        message ?? 'Carregando…',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  @override
  State<ComprovanteScreen> createState() => _ComprovanteScreenState();
}

class _ComprovanteScreenState extends State<ComprovanteScreen> {
  String? _previewError;

  @override
  Widget build(BuildContext context) {
    final body =
        _previewError == null
            ? PdfPreview(
              allowSharing: true,
              allowPrinting: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              actions: const [],
              initialPageFormat: PdfPageFormat.a4,
              pdfFileName: 'comprovante.pdf',
              onError: (context, error) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _previewError = error.toString());
                });
                return const SizedBox.shrink();
              },
              build: (format) async => widget.bytes,
            )
            : _PreviewFallback(error: _previewError!, bytes: widget.bytes);

    return Scaffold(appBar: AppBar(title: const Text('Documento')), body: body);
  }
}

class _PreviewFallback extends StatelessWidget {
  final String error;
  final Uint8List bytes;
  const _PreviewFallback({required this.error, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'Não foi possível exibir o PDF.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Compartilhar/baixar PDF'),
              onPressed:
                  () => Printing.sharePdf(
                    bytes: bytes,
                    filename: 'comprovante.pdf',
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---- Construção do PDF -----------------------------------------------------

class _ComprovanteBuilder {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<Uint8List> buildForPedido(String pedidoId) async {
    final u = _auth.currentUser;
    if (u == null) {
      throw Exception('Usuário não logado');
    }
    final uid = u.uid;

    // Pedido
    final pedSnap = await _fs.collection('pedidos').doc(pedidoId).get();
    if (!pedSnap.exists) throw Exception('Pedido não encontrado');
    final ped = pedSnap.data() as Map<String, dynamic>;

    // ==== Descobrir companyId para buscar o perfil_negocio ====
    String? companyId;

    // 1) Se o pedido já tiver companyId, usa ele
    final rawPedCompanyId = ped['companyId'];
    if (rawPedCompanyId != null) {
      companyId = rawPedCompanyId.toString().trim();
    }

    // 2) Se não tiver no pedido, pega companyId da coleção users (usuário logado)
    if (companyId == null || companyId.isEmpty) {
      final userDoc = await _fs.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final dataUser = userDoc.data() as Map<String, dynamic>;
        final rawUserCompanyId = dataUser['companyId'];
        if (rawUserCompanyId != null) {
          companyId = rawUserCompanyId.toString().trim();
        }
      }
    }

    // 3) Carrega o perfil_negocio usando o companyId como ID do documento
    Map<String, dynamic> perfil = {};
    if (companyId != null && companyId.isNotEmpty) {
      final perfilDoc =
          await _fs.collection('perfil_negocio').doc(companyId).get();
      if (perfilDoc.exists) {
        perfil = perfilDoc.data() as Map<String, dynamic>;
      }
    }

    // Cliente (busca em "contatos" e depois "clientes")
    Map<String, dynamic> cliente = {};
    final String? clienteId = ped['clienteId']?.toString();
    if (clienteId != null && clienteId.isNotEmpty) {
      cliente = await _tryReadById(['contatos', 'clientes'], clienteId) ?? {};
    }

    // Logo (opcional)
    pw.ImageProvider? logo;
    final logoUrl = (perfil['logoUrl'] ?? '').toString();
    if (logoUrl.isNotEmpty) {
      try {
        logo = await networkImage(logoUrl);
      } catch (_) {}
    }

    final doc = pw.Document();

    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dataDoc = (ped['data'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dataFmt = DateFormat('dd/MM/yyyy').format(dataDoc);

    // ===== Itens do pedido =====
    final itensProdutos =
        ((ped['itensProdutos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final itensServicos =
        ((ped['itensServicos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    // Subtotais: usa campos prontos, senão calcula via soma
    final subtotalProdutos =
        (ped['subtotalProdutos'] as num?)?.toDouble() ??
        _sumItens(itensProdutos);
    final subtotalServicos =
        (ped['subtotalServicos'] as num?)?.toDouble() ??
        _sumItens(itensServicos);

    final subtotal =
        (ped['subtotal'] as num?)?.toDouble() ??
        (subtotalProdutos + subtotalServicos);
    final descontoValor = (ped['descontoValor'] as num?)?.toDouble() ?? 0;
    final outrasTaxas = (ped['outrasTaxas'] as num?)?.toDouble() ?? 0;
    final total =
        (ped['total'] as num?)?.toDouble() ??
        (subtotal - descontoValor + outrasTaxas);

    final meiosPag =
        (ped['meiosPagamento'] as List? ?? [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();

    final clausulas = (ped['clausulasContratuais'] ?? '').toString();
    final infoAdic = (ped['infoAdicionais'] ?? '').toString();

    // Página
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 32),
          textDirection: pw.TextDirection.ltr,
        ),
        build:
            (ctx) => [
              _header(logo, perfil, dataFmt),
              pw.SizedBox(height: 12),
              _barTitle('Orcamento ${_numeroLabel(ped)}'), // "ç" -> "c"
              pw.SizedBox(height: 8),
              _clienteBox(cliente),

              if (itensServicos.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                _barTitle('Servicos'),
                pw.SizedBox(height: 6),
                _tabelaItens(itensServicos, fmt),
              ],

              if (itensProdutos.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                _barTitle('Produtos'),
                pw.SizedBox(height: 6),
                _tabelaItens(itensProdutos, fmt),
              ],

              pw.SizedBox(height: 10),
              _totais(
                subtotal: subtotal,
                desc: descontoValor,
                outras: outrasTaxas,
                total: total,
                fmt: fmt,
                subtotalProdutos:
                    subtotalProdutos > 0 ? subtotalProdutos : null,
                subtotalServicos:
                    subtotalServicos > 0 ? subtotalServicos : null,
              ),

              pw.SizedBox(height: 16),
              _barTitle('Pagamento'),
              pw.SizedBox(height: 6),
              _meiosPagamento(meiosPag, perfil),

              if (clausulas.trim().isNotEmpty) ...[
                pw.SizedBox(height: 16),
                _barTitle('Clausulas contratuais'),
                pw.SizedBox(height: 6),
                pw.Text(
                  _sanitizeAscii(clausulas),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],

              if (infoAdic.trim().isNotEmpty) ...[
                pw.SizedBox(height: 16),
                _barTitle('Informacoes adicionais'),
                pw.SizedBox(height: 6),
                pw.Text(
                  _sanitizeAscii(infoAdic),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],

              pw.SizedBox(height: 18),
              _assinatura(
                DateFormat('dd/MM/yyyy', 'pt_BR').format(DateTime.now()),
                perfil,
              ),
            ],
      ),
    );

    return doc.save();
  }

  // ----- Blocos PDF ---------------------------------------------------------

  pw.Widget _header(
    pw.ImageProvider? logo,
    Map<String, dynamic> perfil,
    String dataFmt,
  ) {
    final empresaNome = (perfil['empresa_nome'] ?? '').toString();
    final razao = (perfil['empresa_razao'] ?? '').toString();
    final cnpj = (perfil['empresa_cnpj'] ?? '').toString();

    final tel1 = (perfil['contato_tel1'] ?? '').toString();
    final tel2 = (perfil['contato_tel2'] ?? '').toString();

    final endLog = (perfil['end_logradouro'] ?? '').toString();
    final endNum = (perfil['end_numero'] ?? '').toString();
    final endBai = (perfil['end_bairro'] ?? '').toString();
    final endCid = (perfil['end_cidade'] ?? '').toString();
    final endUF = (perfil['end_uf'] ?? '').toString();
    final endCEP = (perfil['end_cep'] ?? '').toString();

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 1, color: PdfColors.grey300),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null)
            pw.Container(
              width: 64,
              height: 64,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  empresaNome.isEmpty ? '-' : empresaNome,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (razao.isNotEmpty)
                  pw.Text(razao, style: const pw.TextStyle(fontSize: 10)),
                if (cnpj.isNotEmpty)
                  pw.Text(
                    'CNPJ: $cnpj',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                pw.Text(
                  _joinNotEmptyAscii([
                    '$endLog, $endNum',
                    endBai,
                    _joinNotEmptyAscii([endCid, endUF], sep: ' - '),
                    'CEP $endCEP',
                  ]),
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Row(
                  children: [
                    if (tel1.isNotEmpty)
                      pw.Text(
                        'Tel: $tel1  ',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    if (tel2.isNotEmpty)
                      pw.Text(
                        '| $tel2',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(dataFmt, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  pw.Widget _barTitle(String text) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    color: PdfColors.grey300,
    child: pw.Text(
      text,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
    ),
  );

  pw.Widget _clienteBox(Map<String, dynamic> c) {
    final nome = (c['nome'] ?? c['razaoSocial'] ?? '').toString();
    final cpf = (c['cpf'] ?? '').toString();
    final cnpj = (c['cnpj'] ?? '').toString();
    final tel = (c['telefone'] ?? c['whatsapp'] ?? '').toString();
    final email = (c['email'] ?? '').toString();

    final end = (c['endereco'] as Map?) ?? {};
    final rua = (end['rua'] ?? '').toString();
    final num = (end['numero'] ?? '').toString();
    final bai = (end['bairro'] ?? '').toString();
    final cid = (end['cidade'] ?? '').toString();
    final uf = (end['estado'] ?? '').toString();
    final cep = (end['cep'] ?? '').toString();
    final comp = (end['complemento'] ?? '').toString();

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            nome.isEmpty ? 'Cliente: -' : 'Cliente: $nome',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          pw.SizedBox(height: 2),
          if (cpf.isNotEmpty)
            pw.Text('CPF: $cpf', style: const pw.TextStyle(fontSize: 10)),
          if (cnpj.isNotEmpty)
            pw.Text('CNPJ: $cnpj', style: const pw.TextStyle(fontSize: 10)),
          if ([
            rua,
            num,
            bai,
            cid,
            uf,
            cep,
          ].any((e) => e.toString().trim().isNotEmpty))
            pw.Text(
              _joinNotEmptyAscii([
                '$rua, $num',
                bai,
                _joinNotEmptyAscii([cid, uf], sep: ' - '),
                'CEP $cep',
                comp,
              ]),
              style: const pw.TextStyle(fontSize: 10),
            ),
          if (tel.isNotEmpty || email.isNotEmpty)
            pw.Text(
              _joinNotEmptyAscii(['Tel: $tel', email]),
              style: const pw.TextStyle(fontSize: 10),
            ),
        ],
      ),
    );
  }

  pw.Widget _tabelaItens(List<Map<String, dynamic>> itens, NumberFormat fmt) {
    final headers = ['Descricao', 'Qtd', 'UN', 'Preco', 'Total']; // sem acentos

    String _fmtQtd(double q) =>
        q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

    final data =
        itens.map((it) {
          final nome = (it['nome'] ?? '').toString();
          final qtdNum = (it['quantidade'] as num?)?.toDouble() ?? 0;
          final un = (it['unidade'] ?? '').toString();
          final vu = (it['valorUnitario'] as num?)?.toDouble() ?? 0;
          final tot = (it['total'] as num?)?.toDouble() ?? (vu * qtdNum);
          return [nome, _fmtQtd(qtdNum), un, fmt.format(vu), fmt.format(tot)];
        }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 10),
      border: null,
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(0.8),
        2: pw.FlexColumnWidth(0.8),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.2),
      },
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _totais({
    required double subtotal,
    required double desc,
    required double outras,
    required double total,
    required NumberFormat fmt,
    double? subtotalProdutos,
    double? subtotalServicos,
  }) {
    pw.Widget row(String k, String v, {bool bold = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 260,
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                k,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              pw.Text(
                v,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return pw.Column(
      children: [
        if (subtotalServicos != null)
          row('Subtotal servicos', fmt.format(subtotalServicos)),
        if (subtotalProdutos != null)
          row('Subtotal produtos', fmt.format(subtotalProdutos)),
        row('Subtotal', fmt.format(subtotal)),
        if (desc > 0) row('Desconto', '- ${fmt.format(desc)}'),
        if (outras > 0) row('Outras taxas', fmt.format(outras)),
        pw.SizedBox(height: 4),
        row('Total', fmt.format(total), bold: true),
      ],
    );
  }

  pw.Widget _meiosPagamento(
    List<String> meiosPed,
    Map<String, dynamic> perfil,
  ) {
    const textoPadrao =
        'Boleto, transferencia bancaria, dinheiro, cheque, cartao de credito, cartao de debito ou pix.';
    final linhas = <String>[];

    // Linha com os meios escolhidos no pedido
    if (meiosPed.isNotEmpty) {
      linhas.add('Meios de pagamento: ${meiosPed.join(', ')}');
    } else {
      linhas.add('Meios de pagamento');
      linhas.add(textoPadrao);
    }

    // Dados bancários / PIX da empresa (perfil_negocio)
    final pix = (perfil['pag_pix'] ?? '').toString();
    final banco = (perfil['pag_banco'] ?? '').toString();
    final agencia = (perfil['pag_agencia'] ?? '').toString();
    final conta = (perfil['pag_conta'] ?? '').toString();
    final favorecido = (perfil['pag_favorecido'] ?? '').toString();
    final obsPag = (perfil['pag_observacoes'] ?? '').toString();

    final temDadosBancarios = [
      pix,
      banco,
      agencia,
      conta,
      favorecido,
      obsPag,
    ].any((s) => s.trim().isNotEmpty);

    if (temDadosBancarios) {
      linhas.add('');
      linhas.add('Dados para pagamento:');

      if (favorecido.isNotEmpty) {
        linhas.add('Favorecido: $favorecido');
      }
      if (pix.isNotEmpty) {
        linhas.add('Chave PIX: $pix');
      }
      if (banco.isNotEmpty || agencia.isNotEmpty || conta.isNotEmpty) {
        final partes = <String>[];
        if (banco.isNotEmpty) partes.add('Banco: $banco');
        if (agencia.isNotEmpty) partes.add('Agencia: $agencia');
        if (conta.isNotEmpty) partes.add('Conta: $conta');
        linhas.add(partes.join(' | '));
      }
      if (obsPag.isNotEmpty) {
        linhas.add(obsPag);
      }
    }

    final agradecimento = (perfil['det_agradecimento'] ?? '').toString();
    if (agradecimento.isNotEmpty) {
      linhas.add('');
      linhas.add(agradecimento);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children:
          linhas
              .map((t) => pw.Text(t, style: const pw.TextStyle(fontSize: 10)))
              .toList(),
    );
  }

  pw.Widget _assinatura(String dataHoje, Map<String, dynamic> perfil) {
    final empresa = (perfil['empresa_nome'] ?? '').toString();
    return pw.Column(
      children: [
        pw.Center(
          child: pw.Text(
            dataHoje,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Container(width: 260, height: 1, color: PdfColors.grey500),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            empresa.isEmpty ? 'Assinatura' : empresa,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  String _numeroLabel(Map<String, dynamic> ped) {
    final n = ped['numero'] ?? '';
    final ano = ped['ano'] ?? '';
    final nn = (n is int) ? n.toString().padLeft(3, '0') : n.toString();
    return '$nn-$ano';
  }

  // ===== Util =====

  static String _sanitizeAscii(String s) {
    return s.replaceAll('\r', '').trim();
  }

  static double _sumItens(List<Map<String, dynamic>> itens) {
    double sum = 0;
    for (final it in itens) {
      final qtd = (it['quantidade'] as num?)?.toDouble() ?? 0;
      final vu = (it['valorUnitario'] as num?)?.toDouble() ?? 0;
      final tot = (it['total'] as num?)?.toDouble();
      sum += (tot ?? (qtd * vu));
    }
    return sum;
  }

  static String _joinNotEmptyAscii(List<String> parts, {String sep = ' - '}) =>
      parts.where((e) => e.trim().isNotEmpty).join(sep);

  Future<Map<String, dynamic>?> _tryReadById(
    List<String> collections,
    String id,
  ) async {
    for (final col in collections) {
      final snap = await _fs.collection(col).doc(id).get();
      if (snap.exists) return snap.data() as Map<String, dynamic>;
    }
    return null;
  }
}
