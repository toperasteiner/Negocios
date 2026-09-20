import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CatalogoPublicoScreen extends StatefulWidget {
  final String? companyId;
  final String? slugCatalogo;
  final String? nomeEmpresa;

  const CatalogoPublicoScreen({
    super.key,
    this.companyId,
    this.slugCatalogo,
    this.nomeEmpresa,
  }) : assert(companyId != null || slugCatalogo != null);

  @override
  State<CatalogoPublicoScreen> createState() => _CatalogoPublicoScreenState();
}

class _CatalogoPublicoScreenState extends State<CatalogoPublicoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _money = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final TextEditingController _buscaController = TextEditingController();
  final TextEditingController _clienteNomeController = TextEditingController();
  final TextEditingController _clienteTelefoneController =
      TextEditingController();
  final TextEditingController _clienteEmailController = TextEditingController();
  final TextEditingController _observacaoController = TextEditingController();

  String _busca = '';
  final List<_ItemCarrinho> _carrinho = [];

  String? _companyIdResolvido;
  String? _nomeEmpresaResolvido;
  bool _carregandoEmpresa = true;
  String? _erroEmpresa;

  String? _categoriaSelecionadaId;
  String _categoriaSelecionadaNome = 'Todos';
  String? _bannerUrl;

  String? _cnpj;
  String? _telefone;
  String? _endereco;
  String? _instagram;
  String? _facebook;
  String? _whatsapp;

  String _produtosSemEstoque = 'exibir_normalmente';
  bool _funciona24x7 = false;
  bool _aceitaPedidoForaHorario = true;
  Map<String, dynamic> _horarioFuncionamento = {};
  final List<_FormaEntregaCatalogo> _formasEntrega = [];
  String? _formaEntregaSelecionadaId;

  @override
  void initState() {
    super.initState();

    _resolverEmpresa();

    _buscaController.addListener(() {
      setState(() {
        _busca = _buscaController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _clienteNomeController.dispose();
    _clienteTelefoneController.dispose();
    _clienteEmailController.dispose();
    _observacaoController.dispose();
    super.dispose();
  }

  double get _subtotalCarrinho {
    return _carrinho.fold(0.0, (total, item) => total + item.total);
  }

  double get _valorEntregaSelecionada {
    final forma = _formaEntregaSelecionada;
    return forma?.valor ?? 0.0;
  }

  double get _totalPedido {
    return _subtotalCarrinho + _valorEntregaSelecionada;
  }

  int get _quantidadeTotal {
    return _carrinho.fold(0, (total, item) => total + item.quantidade);
  }

  _FormaEntregaCatalogo? get _formaEntregaSelecionada {
    if (_formaEntregaSelecionadaId == null) return null;

    try {
      return _formasEntrega.firstWhere(
        (forma) => forma.id == _formaEntregaSelecionadaId,
      );
    } catch (_) {
      return null;
    }
  }

  String? _textoValido(dynamic valor) {
    final texto = valor?.toString().trim();
    if (texto == null || texto.isEmpty) return null;
    return texto;
  }

  void _preencherDadosEmpresa(Map<String, dynamic>? perfilData) {
    _cnpj = _textoValido(perfilData?['empresa_cnpj']);

    _telefone = _textoValido(
      perfilData?['contato_tel1'] ?? perfilData?['contato_tel2'],
    );

    _instagram = _textoValido(perfilData?['social_instagram']);
    _facebook = _textoValido(perfilData?['social_facebook']);
    _whatsapp = _textoValido(perfilData?['contato_tel1']);

    _endereco = [
      perfilData?['end_logradouro'],
      perfilData?['end_numero'],
      perfilData?['end_complemento'],
      perfilData?['end_bairro'],
      perfilData?['end_cidade'],
      perfilData?['end_uf'],
      perfilData?['end_cep'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', ');

    if (_endereco!.isEmpty) {
      _endereco = null;
    }
  }

  Future<void> _resolverEmpresa() async {
    try {
      final companyIdParam = widget.companyId?.trim();

      if (companyIdParam != null && companyIdParam.isNotEmpty) {
        final catalogoDoc =
            await _firestore.collection('catalogo').doc(companyIdParam).get();

        final perfilDoc =
            await _firestore
                .collection('perfil_negocio')
                .doc(companyIdParam)
                .get();

        final perfilData = perfilDoc.data();
        final data = catalogoDoc.data();

        print('PERFIL DATA: $perfilData');

        _preencherDadosEmpresa(perfilData);
        _aplicarConfiguracaoCatalogo(data);

        setState(() {
          _companyIdResolvido = companyIdParam;

          _nomeEmpresaResolvido =
              widget.nomeEmpresa ??
              perfilData?['empresa_nome']?.toString() ??
              perfilData?['empresa_razao']?.toString() ??
              data?['nome']?.toString() ??
              data?['nomeEmpresa']?.toString() ??
              'Catálogo';

          _bannerUrl =
              perfilData?['bannerCatalogoUrl']?.toString() ??
              perfilData?['bannerUrl']?.toString() ??
              data?['bannerCatalogoUrl']?.toString() ??
              data?['bannerUrl']?.toString() ??
              data?['fotoCapaUrl']?.toString();

          _carregandoEmpresa = false;
          _erroEmpresa = null;
        });

        return;
      }

      final slug = widget.slugCatalogo?.trim();

      if (slug == null || slug.isEmpty) {
        setState(() {
          _carregandoEmpresa = false;
          _erroEmpresa = 'Catálogo não informado.';
        });
        return;
      }

      final snap =
          await _firestore
              .collection('catalogo')
              .where('catalogoSlug', isEqualTo: slug)
              .where('catalogoAtivo', isEqualTo: true)
              .limit(1)
              .get();

      if (snap.docs.isEmpty) {
        setState(() {
          _carregandoEmpresa = false;
          _erroEmpresa = 'Catálogo não encontrado ou inativo.';
        });
        return;
      }

      final doc = snap.docs.first;
      final data = doc.data();

      final companyId = (data['companyId'] ?? doc.id).toString();

      final perfilDoc =
          await _firestore.collection('perfil_negocio').doc(companyId).get();

      final perfilData = perfilDoc.data();

      _preencherDadosEmpresa(perfilData);
      _aplicarConfiguracaoCatalogo(data);

      setState(() {
        _companyIdResolvido = companyId;
        _nomeEmpresaResolvido =
            widget.nomeEmpresa ??
            perfilData?['empresa_nome']?.toString() ??
            perfilData?['empresa_razao']?.toString() ??
            data['nome']?.toString() ??
            data['nomeEmpresa']?.toString() ??
            'Catálogo';

        _bannerUrl =
            perfilData?['bannerCatalogoUrl']?.toString() ??
            perfilData?['bannerUrl']?.toString() ??
            data['bannerCatalogoUrl']?.toString() ??
            data['bannerUrl']?.toString() ??
            data['fotoCapaUrl']?.toString();

        _carregandoEmpresa = false;
        _erroEmpresa = null;
      });
    } catch (e) {
      setState(() {
        _carregandoEmpresa = false;
        _erroEmpresa = 'Erro ao carregar catálogo: $e';
      });
    }
  }

  void _aplicarConfiguracaoCatalogo(Map<String, dynamic>? data) {
    _produtosSemEstoque =
        (data?['produtosSemEstoque'] ?? 'exibir_normalmente').toString();

    _funciona24x7 = data?['funciona24x7'] == true;
    _aceitaPedidoForaHorario =
        (data?['aceitaPedidoForaHorario'] ?? true) == true;

    final horarioRaw = data?['horarioFuncionamento'];
    if (horarioRaw is Map<String, dynamic>) {
      _horarioFuncionamento = horarioRaw;
    } else if (horarioRaw is Map) {
      _horarioFuncionamento = Map<String, dynamic>.from(horarioRaw);
    }

    _formasEntrega.clear();

    final formasRaw = data?['formasEntrega'];
    if (formasRaw is List) {
      for (final item in formasRaw) {
        if (item is Map) {
          final ativo = (item['ativo'] ?? true) == true;
          if (!ativo) continue;

          _formasEntrega.add(
            _FormaEntregaCatalogo(
              id: (item['id'] ?? '').toString(),
              tipo: (item['tipo'] ?? '').toString(),
              nome: (item['nome'] ?? 'Entrega').toString(),
              descricao: (item['descricao'] ?? '').toString(),
              prazo: (item['prazo'] ?? '').toString(),
              valor: _toDouble(item['valor']),
            ),
          );
        }
      }
    }

    if (_formasEntrega.isNotEmpty) {
      _formaEntregaSelecionadaId = _formasEntrega.first.id;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamCategorias() {
    return _firestore
        .collection('categorias')
        .where('companyId', isEqualTo: _companyIdResolvido!)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamProdutos() {
    return _firestore
        .collection('produtos')
        .where('companyId', isEqualTo: _companyIdResolvido!)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamServicos() {
    return _firestore
        .collection('servicos')
        .where('companyId', isEqualTo: _companyIdResolvido!)
        .snapshots();
  }

  bool _itemAtivo(Map<String, dynamic> data) {
    final ativo = data['ativo'];
    if (ativo != null && ativo != true) return false;
    return true;
  }

  bool _produtoSemEstoque(Map<String, dynamic> data) {
    final controlaEstoque = (data['controlaEstoque'] ?? false) == true;
    if (!controlaEstoque) return false;

    final estoque = _toDouble(data['estoque']);
    return estoque <= 0;
  }

  bool _produtoPodeAparecer(Map<String, dynamic> data, String tipo) {
    if (tipo != 'produto') return true;

    final semEstoque = _produtoSemEstoque(data);

    if (!semEstoque) return true;

    if (_produtosSemEstoque == 'nao_mostrar') return false;

    return true;
  }

  bool _produtoPodeAdicionar(Map<String, dynamic> data, String tipo) {
    if (tipo != 'produto') return true;

    final semEstoque = _produtoSemEstoque(data);

    if (!semEstoque) return true;

    if (_produtosSemEstoque == 'mostrar_nao_disponivel') return false;

    return true;
  }

  bool _passaFiltro(Map<String, dynamic> data, String tipo) {
    if (!_itemAtivo(data)) return false;

    if (!_produtoPodeAparecer(data, tipo)) return false;

    if (_categoriaSelecionadaId != null &&
        data['categoriaId'] != _categoriaSelecionadaId) {
      return false;
    }

    if (_busca.isEmpty) return true;

    final nome = (data['nome'] ?? '').toString().toLowerCase();
    final descricao =
        (data['descricao'] ?? data['detalhes'] ?? '').toString().toLowerCase();

    return nome.contains(_busca) || descricao.contains(_busca);
  }

  bool _categoriaAtiva(Map<String, dynamic> data) {
    final ativo = data['ativo'];
    if (ativo != null && ativo != true) return false;
    return true;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value.toString().replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0.0;
  }

  /*List<String> _getImagens(Map<String, dynamic> data) {
    final imagens = <String>[];

    final fotos = data['fotos'];
    if (fotos is List) {
      for (final f in fotos) {
        final url = f?.toString().trim();
        if (url != null && url.isNotEmpty) imagens.add(url);
      }
    }

    final campos = [
      data['fotoUrl'],
      data['imagemUrl'],
      data['imageUrl'],
      data['urlImagem'],
      data['foto'],
    ];

    for (final campo in campos) {
      final url = campo?.toString().trim();
      if (url != null && url.isNotEmpty && !imagens.contains(url)) {
        imagens.add(url);
      }
    }

    return imagens;
  }*/
  List<String> _getImagens(Map<String, dynamic> data) {
    final imagens = <String>[];

    void adicionar(dynamic valor) {
      if (valor == null) return;

      String? url;

      if (valor is String) {
        url = valor.trim();
      } else if (valor is Map) {
        url =
            valor['url']?.toString().trim() ??
            valor['downloadUrl']?.toString().trim() ??
            valor['fotoUrl']?.toString().trim() ??
            valor['imagemUrl']?.toString().trim() ??
            valor['imageUrl']?.toString().trim() ??
            valor['storagePath']?.toString().trim() ??
            valor['path']?.toString().trim();
      }

      if (url == null || url.isEmpty) return;

      if (!imagens.contains(url)) {
        imagens.add(url);
      }
    }

    final fotos = data['fotos'];

    if (fotos is List) {
      for (final foto in fotos) {
        adicionar(foto);
      }
    } else {
      adicionar(fotos);
    }

    final fotosAprovadas = data['fotosAprovadas'];

    if (fotosAprovadas is List) {
      for (final foto in fotosAprovadas) {
        adicionar(foto);
      }
    }

    final imagemModeracao = data['imagemModeracao'];

    if (imagemModeracao is Map) {
      final status =
          (imagemModeracao['status'] ?? '').toString().trim().toLowerCase();

      if (status == 'aprovada' || status == 'aprovado' || status.isEmpty) {
        adicionar(imagemModeracao);
      }
    } else {
      adicionar(imagemModeracao);
    }

    adicionar(data['fotoUrl']);
    adicionar(data['imagemUrl']);
    adicionar(data['imageUrl']);
    adicionar(data['urlImagem']);
    adicionar(data['foto']);
    adicionar(data['imagem']);
    adicionar(data['storagePath']);
    adicionar(data['fotoStoragePath']);

    return imagens;
  }

  double _getPrecoVenda(Map<String, dynamic> data) {
    return _toDouble(
      data['precoVenda'] ??
          data['valorVenda'] ??
          data['preco'] ??
          data['valor'] ??
          data['valorUnitario'],
    );
  }

  String _getDescricao(Map<String, dynamic> data) {
    return (data['descricao'] ?? data['detalhes'] ?? '').toString();
  }

  String _diaKey(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'segunda';
      case DateTime.tuesday:
        return 'terca';
      case DateTime.wednesday:
        return 'quarta';
      case DateTime.thursday:
        return 'quinta';
      case DateTime.friday:
        return 'sexta';
      case DateTime.saturday:
        return 'sabado';
      case DateTime.sunday:
        return 'domingo';
      default:
        return '';
    }
  }

  int _minutosAgora(DateTime date) {
    return date.hour * 60 + date.minute;
  }

  int _minutosHora(String hora) {
    final parts = hora.split(':');
    if (parts.length != 2) return 0;

    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    return h * 60 + m;
  }

  bool _periodoContemAgora({
    required int agora,
    required String inicio,
    required String fim,
  }) {
    final ini = _minutosHora(inicio);
    final end = _minutosHora(fim);

    if (end <= ini) {
      return agora >= ini || agora <= end;
    }

    return agora >= ini && agora <= end;
  }

  bool _estaAbertoAgora() {
    if (_funciona24x7) return true;

    final now = DateTime.now();
    final hojeKey = _diaKey(now);
    final ontemKey = _diaKey(now.subtract(const Duration(days: 1)));
    final agora = _minutosAgora(now);

    bool abertoNoDia(String diaKey, {required bool considerarVirada}) {
      final dia = _horarioFuncionamento[diaKey];

      if (dia is! Map) return false;
      if (dia['aberto'] != true) return false;

      final periodos = dia['periodos'];
      if (periodos is! List) return false;

      for (final p in periodos) {
        if (p is! Map) continue;

        final inicio = (p['inicio'] ?? '').toString();
        final fim = (p['fim'] ?? '').toString();

        if (inicio.isEmpty || fim.isEmpty) continue;

        final ini = _minutosHora(inicio);
        final end = _minutosHora(fim);
        final cruzaDia = (p['cruzaDia'] == true) || end <= ini;

        if (considerarVirada && !cruzaDia) continue;

        if (_periodoContemAgora(agora: agora, inicio: inicio, fim: fim)) {
          return true;
        }
      }

      return false;
    }

    return abertoNoDia(hojeKey, considerarVirada: false) ||
        abertoNoDia(ontemKey, considerarVirada: true);
  }

  String _statusFuncionamentoTexto() {
    if (_funciona24x7) return '';

    if (_estaAbertoAgora()) return 'Aberto agora';

    if (_aceitaPedidoForaHorario) {
      return 'Fechado agora, mas aceitando pedidos';
    }

    return 'Fechado agora';
  }

  Color _statusFuncionamentoCor() {
    if (_funciona24x7 || _estaAbertoAgora()) return Colors.green;
    if (_aceitaPedidoForaHorario) return Colors.orange;
    return Colors.red;
  }

  void _adicionarAoCarrinho({
    required String id,
    required String tipo,
    required Map<String, dynamic> data,
  }) {
    if (!_produtoPodeAdicionar(data, tipo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto não disponível no momento.')),
      );
      return;
    }

    final nome = (data['nome'] ?? 'Item sem nome').toString();
    final preco = _getPrecoVenda(data);
    final imagens = _getImagens(data);
    final imagem = imagens.isNotEmpty ? imagens.first : null;

    final index = _carrinho.indexWhere(
      (item) => item.id == id && item.tipo == tipo,
    );

    setState(() {
      if (index >= 0) {
        _carrinho[index].quantidade++;
      } else {
        _carrinho.add(
          _ItemCarrinho(
            id: id,
            tipo: tipo,
            nome: nome,
            quantidade: 1,
            valorUnitario: preco,
            imagemUrl: imagem,
          ),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$nome adicionado ao carrinho.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _abrirCarrinho() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Carrinho',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_carrinho.isEmpty)
                        const Expanded(
                          child: Center(
                            child: Text('Seu carrinho está vazio.'),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: _carrinho.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = _carrinho[index];

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _imagemItem(item.imagemUrl),
                                title: Text(
                                  item.nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.tipoLabel} • ${_money.format(item.valorUnitario)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (item.quantidade > 1) {
                                            item.quantidade--;
                                          } else {
                                            _carrinho.removeAt(index);
                                          }
                                        });
                                        setModalState(() {});
                                      },
                                    ),
                                    Text(
                                      item.quantidade.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          item.quantidade++;
                                        });
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Subtotal',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _money.format(_subtotalCarrinho),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _carrinho.isEmpty
                                  ? null
                                  : () {
                                    Navigator.pop(context);
                                    _abrirFinalizacaoPedido();
                                  },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Finalizar pedido'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _abrirFinalizacaoPedido() {
    final abertoAgora = _estaAbertoAgora();

    if (!abertoAgora && !_aceitaPedidoForaHorario) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A loja está fechada e não aceita pedidos fora do horário.',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final forma = _formaEntregaSelecionada;

            return AlertDialog(
              title: const Text('Finalizar pedido'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    if (!abertoAgora && _aceitaPedidoForaHorario) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'A loja está fechada agora. Seu pedido será enviado, mas poderá ser atendido no próximo horário de funcionamento.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    TextField(
                      controller: _clienteNomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do cliente',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _clienteTelefoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone / WhatsApp',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _clienteEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_formasEntrega.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _formaEntregaSelecionadaId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Forma de entrega',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            _formasEntrega.map((entrega) {
                              return DropdownMenuItem(
                                value: entrega.id,
                                child: SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width * 0.55,
                                  child: Text(
                                    entrega.valor > 0
                                        ? '${entrega.nome} - ${_money.format(entrega.valor)}'
                                        : entrega.nome,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _formaEntregaSelecionadaId = value;
                          });
                          setDialogState(() {});
                        },
                      ),
                      if (forma != null &&
                          (forma.descricao.isNotEmpty ||
                              forma.prazo.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            [
                              if (forma.descricao.isNotEmpty) forma.descricao,
                              if (forma.prazo.isNotEmpty) forma.prazo,
                            ].join(' • '),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _observacaoController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observação',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ResumoPedido(
                      money: _money,
                      subtotal: _subtotalCarrinho,
                      entrega: _valorEntregaSelecionada,
                      total: _totalPedido,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: _salvarPedido,
                  child: const Text('Enviar pedido'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _salvarPedido() async {
    final abertoAgora = _estaAbertoAgora();

    if (!abertoAgora && !_aceitaPedidoForaHorario) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A loja está fechada e não aceita pedidos fora do horário.',
          ),
        ),
      );
      return;
    }

    final agora = DateTime.now();
    final ano = agora.year;

    final indexSnap =
        await _firestore
            .collection('pedidos_index')
            .where('scope', isEqualTo: _companyIdResolvido)
            .where('ano', isEqualTo: ano)
            .orderBy('numero', descending: true)
            .limit(1)
            .get();

    final proximoNumero =
        indexSnap.docs.isEmpty
            ? 1
            : ((_toDouble(indexSnap.docs.first.data()['numero']).toInt()) + 1);

    final nomeCliente = _clienteNomeController.text.trim();
    final telefoneCliente = _clienteTelefoneController.text.trim();
    final emailCliente = _clienteEmailController.text.trim();

    if (nomeCliente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do cliente.')),
      );
      return;
    }

    if (telefoneCliente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o telefone do cliente.')),
      );
      return;
    }

    if (_companyIdResolvido == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Catálogo indisponível.')));
      return;
    }

    final formaEntrega = _formaEntregaSelecionada;

    try {
      final batch = _firestore.batch();

      final clienteRef = _firestore.collection('clientes').doc();

      batch.set(clienteRef, {
        'nome': nomeCliente,
        'nomeLower': nomeCliente.toLowerCase(),
        'telefone': null,
        'whatsapp': telefoneCliente,
        'email': emailCliente.isEmpty ? null : emailCliente,
        'cpf': null,
        'cnpj': null,
        'razaoSocial': null,
        'tipoCliente': 'pf',
        'isCliente': true,
        'isWebCliente': true,
        'isFornecedor': false,
        'perfilRelacionamento': 'WEB',
        'endereco': {
          'cep': null,
          'rua': null,
          'numero': null,
          'complemento': null,
          'bairro': null,
          'cidade': null,
          'estado': null,
        },
        'observacao': 'Cliente cadastrado pelo catálogo público.',
        'companyId': _companyIdResolvido,
        'userId': _companyIdResolvido,
        'createdByUid': _companyIdResolvido,
        'origem': 'catalogo_publico',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final pedidoRef = _firestore.collection('pedidos').doc();

      final pedidoIndexRef = _firestore.collection('pedidos_index').doc();

      final pedidoPagamentoRef =
          _firestore.collection('pedido_pagamento').doc();

      final itensProdutos =
          _carrinho
              .where((item) => item.tipo == 'produto')
              .map(
                (item) => {
                  'refId': item.id,
                  'nome': item.nome,
                  'quantidade': item.quantidade.toDouble(),
                  'valorUnitario': item.valorUnitario,
                  'total': item.total,
                  'subtotalVenda': item.total,
                  'custoUnitario': 0.0,
                  'subtotalCusto': 0.0,
                  'lucroItem': item.total,
                  'unidade': 'UN',
                },
              )
              .toList();

      final itensServicos =
          _carrinho
              .where((item) => item.tipo == 'servico')
              .map(
                (item) => {
                  'refId': item.id,
                  'nome': item.nome,
                  'quantidade': item.quantidade.toDouble(),
                  'valorUnitario': item.valorUnitario,
                  'total': item.total,
                  'subtotalVenda': item.total,
                  'custoUnitario': 0.0,
                  'subtotalCusto': 0.0,
                  'lucroItem': item.total,
                },
              )
              .toList();

      final subtotalProdutos = itensProdutos.fold<double>(
        0.0,
        (total, item) => total + (item['total'] as double),
      );

      final subtotalServicos = itensServicos.fold<double>(
        0.0,
        (total, item) => total + (item['total'] as double),
      );

      batch.set(pedidoRef, {
        'companyId': _companyIdResolvido,
        'clienteId': clienteRef.id,
        'cliente': nomeCliente,
        'clienteNome': nomeCliente,
        'clienteTelefone': telefoneCliente,
        'clienteEmail': emailCliente,
        'itensProdutos': itensProdutos,
        'itensServicos': itensServicos,
        'subtotalProdutos': subtotalProdutos,
        'subtotalServicos': subtotalServicos,
        'subtotal': subtotalProdutos + subtotalServicos,
        'taxaEntrega': _valorEntregaSelecionada,
        'total':
            (subtotalProdutos + subtotalServicos) + _valorEntregaSelecionada,
        'entrega':
            formaEntrega == null
                ? null
                : {
                  'id': formaEntrega.id,
                  'tipo': formaEntrega.tipo,
                  'nome': formaEntrega.nome,
                  'descricao': formaEntrega.descricao,
                  'prazo': formaEntrega.prazo,
                  'valor': formaEntrega.valor,
                },
        'horarioFuncionamento': {
          'abertoNoMomento': abertoAgora,
          'aceitaPedidoForaHorario': _aceitaPedidoForaHorario,
          'status': _statusFuncionamentoTexto(),
        },
        'observacao': _observacaoController.text.trim(),
        'origem': 'catalogo_publico',
        'status': 'aguardando_aprovacao_web',
        'situacao': 'Aberto',
        'data': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
        'ano': ano,
        'numero': proximoNumero,
      });

      batch.set(pedidoPagamentoRef, {
        'companyId': _companyIdResolvido,
        'userId': _companyIdResolvido,
        'createdByUid': _companyIdResolvido,

        'pedidoId': pedidoRef.id,
        'tipo': 'avista',
        'numeroParcelas': 1,
        'totalPedido': _totalPedido,
        'dataPrimeiroPagamento': Timestamp.now(),

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(pedidoIndexRef, {
        'scope': _companyIdResolvido,
        'ano': ano,
        'numero': proximoNumero,
        'pedidoId': pedidoRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;

      Navigator.pop(context);

      setState(() {
        _carrinho.clear();
        _clienteNomeController.clear();
        _clienteTelefoneController.clear();
        _clienteEmailController.clear();
        _observacaoController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido enviado com sucesso.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar pedido: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildFooterLoja() {
    final temInformacao =
        _nomeEmpresaResolvido != null ||
        _telefone != null ||
        _endereco != null ||
        _instagram != null ||
        _facebook != null ||
        _whatsapp != null;

    if (!temInformacao) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      color: Colors.grey.shade900,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Wrap(
            spacing: 40,
            runSpacing: 20,
            children: [
              // COLUNA 1 - EMPRESA
              _footerColuna(
                titulo: _nomeEmpresaResolvido ?? 'Empresa',
                children: [
                  if (_endereco != null)
                    _footerLinha(Icons.location_on_outlined, _endereco!),
                ],
              ),

              // COLUNA 2 - CONTATO
              _footerColuna(
                titulo: 'Contato',
                children: [
                  if (_telefone != null)
                    _footerLinha(Icons.phone_outlined, _telefone!),
                  if (_whatsapp != null)
                    _footerLinha(Icons.chat_outlined, 'WhatsApp: $_whatsapp'),
                ],
              ),

              // COLUNA 3 - REDES
              _footerColuna(
                titulo: 'Redes sociais',
                children: [
                  if (_instagram != null)
                    _footerLinha(Icons.camera_alt_outlined, _instagram!),
                  if (_facebook != null)
                    _footerLinha(Icons.facebook, _facebook!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerColuna({
    required String titulo,
    required List<Widget> children,
  }) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _footerLinha(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLinha(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: Colors.grey.shade800, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaTudo() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamProdutos(),
      builder: (context, produtosSnap) {
        if (produtosSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (produtosSnap.hasError) {
          return const Center(child: Text('Erro ao carregar produtos.'));
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamServicos(),
          builder: (context, servicosSnap) {
            if (servicosSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (servicosSnap.hasError) {
              return const Center(child: Text('Erro ao carregar serviços.'));
            }

            final produtos =
                (produtosSnap.data?.docs ?? []).map((doc) {
                  return _CatalogoItemDoc(
                    id: doc.id,
                    tipo: 'produto',
                    data: doc.data(),
                  );
                }).toList();

            final servicos =
                (servicosSnap.data?.docs ?? []).map((doc) {
                  return _CatalogoItemDoc(
                    id: doc.id,
                    tipo: 'servico',
                    data: doc.data(),
                  );
                }).toList();

            final itens = [...produtos, ...servicos];

            final filtrados =
                itens.where((item) {
                  return _passaFiltro(item.data, item.tipo);
                }).toList();

            filtrados.sort((a, b) {
              final categoriaA =
                  (a.data['categoriaNome'] ?? '').toString().toLowerCase();
              final categoriaB =
                  (b.data['categoriaNome'] ?? '').toString().toLowerCase();

              final compCategoria = categoriaA.compareTo(categoriaB);
              if (compCategoria != 0) return compCategoria;

              final nomeA = (a.data['nome'] ?? '').toString().toLowerCase();
              final nomeB = (b.data['nome'] ?? '').toString().toLowerCase();
              return nomeA.compareTo(nomeB);
            });

            if (filtrados.isEmpty) {
              return const Center(
                child: Text('Nenhum item encontrado nesta categoria.'),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount =
                    width >= 1200
                        ? 4
                        : width >= 900
                        ? 3
                        : width >= 560
                        ? 2
                        : 1;

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = filtrados[index];
                          final data = item.data;
                          final tipo = item.tipo;

                          final podeAdicionar = _produtoPodeAdicionar(
                            data,
                            tipo,
                          );
                          final semEstoque =
                              tipo == 'produto' && _produtoSemEstoque(data);

                          return _ProdutoCard(
                            tipo: tipo,
                            data: data,
                            imagens: _getImagens(data),
                            nome: (data['nome'] ?? 'Sem nome').toString(),
                            descricao: _getDescricao(data),
                            preco: _getPrecoVenda(data),
                            money: _money,
                            podeAdicionar: podeAdicionar,
                            semEstoque: semEstoque,
                            onAdicionar: () {
                              _adicionarAoCarrinho(
                                id: item.id,
                                tipo: tipo,
                                data: data,
                              );
                            },
                          );
                        }, childCount: filtrados.length),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: crossAxisCount == 1 ? 2.15 : 0.78,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildFooterLoja()),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBannerLoja(String titulo) {
    final hasBanner = _bannerUrl != null && _bannerUrl!.trim().isNotEmpty;
    final statusColor = _statusFuncionamentoCor();

    return Container(
      height: 210,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        image:
            hasBanner
                ? DecorationImage(
                  image: NetworkImage(_bannerUrl!),
                  fit: BoxFit.cover,
                )
                : null,
        gradient:
            hasBanner
                ? null
                : LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade300],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.black.withOpacity(0.28),
        ),
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.95),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _statusFuncionamentoTexto(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCategorias() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamCategorias(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        final categorias =
            docs.where((doc) {
              final data = doc.data();
              if (!_categoriaAtiva(data)) return false;

              final tipo = (data['tipo'] ?? 'ambos').toString().toLowerCase();
              return tipo == 'produto' || tipo == 'servico' || tipo == 'ambos';
            }).toList();

        categorias.sort((a, b) {
          final na = (a.data()['nome'] ?? '').toString().toLowerCase();
          final nb = (b.data()['nome'] ?? '').toString().toLowerCase();
          return na.compareTo(nb);
        });

        return Container(
          width: 240,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'Categorias',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _CategoriaTile(
                selected: _categoriaSelecionadaId == null,
                icon: Icons.storefront_outlined,
                title: 'Todos',
                onTap: () {
                  setState(() {
                    _categoriaSelecionadaId = null;
                    _categoriaSelecionadaNome = 'Todos';
                  });
                },
              ),
              ...categorias.map((doc) {
                final data = doc.data();
                final nome = (data['nome'] ?? 'Sem nome').toString();

                return _CategoriaTile(
                  selected: _categoriaSelecionadaId == doc.id,
                  icon: Icons.category_outlined,
                  title: nome,
                  onTap: () {
                    setState(() {
                      _categoriaSelecionadaId = doc.id;
                      _categoriaSelecionadaNome = nome;
                    });
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoriasHorizontal() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _streamCategorias(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        final categorias =
            docs.where((doc) {
              final data = doc.data();
              if (!_categoriaAtiva(data)) return false;
              return true;
            }).toList();

        categorias.sort((a, b) {
          final na = (a.data()['nome'] ?? '').toString().toLowerCase();
          final nb = (b.data()['nome'] ?? '').toString().toLowerCase();
          return na.compareTo(nb);
        });

        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: _categoriaSelecionadaId == null,
              onSelected: (_) {
                setState(() {
                  _categoriaSelecionadaId = null;
                  _categoriaSelecionadaNome = 'Todos';
                });
              },
            ),
            const SizedBox(width: 8),
            ...categorias.map((doc) {
              final nome = (doc.data()['nome'] ?? 'Sem nome').toString();

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(nome),
                  selected: _categoriaSelecionadaId == doc.id,
                  onSelected: (_) {
                    setState(() {
                      _categoriaSelecionadaId = doc.id;
                      _categoriaSelecionadaNome = nome;
                    });
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _imagemItem(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 56,
            height: 56,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _nomeEmpresaResolvido ?? widget.nomeEmpresa ?? 'Catálogo';

    if (_carregandoEmpresa) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_erroEmpresa != null || _companyIdResolvido == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _erroEmpresa ?? 'Catálogo indisponível.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: Row(
        children: [
          if (isWide) _buildMenuCategorias(),
          Expanded(
            child: Column(
              children: [
                _buildBannerLoja(titulo),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    controller: _buscaController,
                    decoration: InputDecoration(
                      hintText: 'Buscar em $_categoriaSelecionadaNome...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (!isWide)
                  SizedBox(height: 54, child: _buildCategoriasHorizontal()),
                Expanded(child: _buildListaTudo()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCarrinho,
        icon: const Icon(Icons.shopping_cart_outlined),
        label: Text(
          _quantidadeTotal == 0 ? 'Carrinho' : 'Carrinho ($_quantidadeTotal)',
        ),
      ),
    );
  }
}

class _ResumoPedido extends StatelessWidget {
  final NumberFormat money;
  final double subtotal;
  final double entrega;
  final double total;

  const _ResumoPedido({
    required this.money,
    required this.subtotal,
    required this.entrega,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _linha('Subtotal', money.format(subtotal)),
        const SizedBox(height: 6),
        _linha(
          'Entrega',
          entrega <= 0 ? 'Sem cobrança' : money.format(entrega),
        ),
        const Divider(height: 18),
        _linha('Total', money.format(total), bold: true),
      ],
    );
  }

  Widget _linha(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            fontSize: bold ? 18 : 14,
          ),
        ),
      ],
    );
  }
}

class _CategoriaTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _CategoriaTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        selected: selected,
        leading: Icon(icon, color: selected ? cs.onPrimaryContainer : null),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? cs.onPrimaryContainer : null,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  final String tipo;
  final Map<String, dynamic> data;
  final List<String> imagens;
  final String nome;
  final String descricao;
  final double preco;
  final NumberFormat money;
  final bool podeAdicionar;
  final bool semEstoque;
  final VoidCallback onAdicionar;

  const _ProdutoCard({
    required this.tipo,
    required this.data,
    required this.imagens,
    required this.nome,
    required this.descricao,
    required this.preco,
    required this.money,
    required this.podeAdicionar,
    required this.semEstoque,
    required this.onAdicionar,
  });

  @override
  Widget build(BuildContext context) {
    final isList = MediaQuery.of(context).size.width < 560;

    if (isList) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _ImagemProdutoCarousel(imagens: imagens, size: 92),
              const SizedBox(width: 12),
              Expanded(child: _conteudo(context)),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _ImagemProdutoCarousel(
                    imagens: imagens,
                    size: double.infinity,
                    wide: true,
                  ),
                ),
                if (semEstoque)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _BadgeIndisponivel(
                      texto: podeAdicionar ? 'Sem estoque' : 'Não disponível',
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: _conteudo(context)),
        ],
      ),
    );
  }

  Widget _conteudo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize:
          MediaQuery.of(context).size.width < 560
              ? MainAxisSize.min
              : MainAxisSize.max,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                nome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (semEstoque && MediaQuery.of(context).size.width < 560)
              _BadgeIndisponivel(
                texto: podeAdicionar ? 'Sem estoque' : 'Não disponível',
              ),
          ],
        ),
        if (descricao.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            descricao,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          money.format(preco),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.width < 560 ? 36 : 44,
          child: ElevatedButton.icon(
            onPressed: podeAdicionar ? onAdicionar : null,
            icon: Icon(
              podeAdicionar ? Icons.add_shopping_cart : Icons.block_outlined,
              size: 18,
            ),
            label: Text(
              podeAdicionar ? 'Adicionar' : 'Não disponível',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _BadgeIndisponivel extends StatelessWidget {
  final String texto;

  const _BadgeIndisponivel({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ImagemProdutoCarousel extends StatefulWidget {
  final List<String> imagens;
  final double size;
  final bool wide;

  const _ImagemProdutoCarousel({
    required this.imagens,
    required this.size,
    this.wide = false,
  });

  @override
  State<_ImagemProdutoCarousel> createState() => _ImagemProdutoCarouselState();
}

class _ImagemProdutoCarouselState extends State<_ImagemProdutoCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  Future<String?> _resolveUrl(String raw) async {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    try {
      final ref =
          raw.startsWith('gs://')
              ? FirebaseStorage.instance.refFromURL(raw)
              : FirebaseStorage.instance.ref(raw);

      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagens.isEmpty) {
      return Container(
        width: widget.wide ? double.infinity : widget.size,
        height: widget.wide ? double.infinity : widget.size,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: widget.wide ? null : BorderRadius.circular(16),
        ),
        child: const Icon(Icons.image_outlined, size: 38),
      );
    }

    Widget botaoSeta({required IconData icon, required VoidCallback onTap}) {
      return Material(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: widget.wide ? BorderRadius.zero : BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            width: widget.wide ? double.infinity : widget.size,
            height: widget.wide ? double.infinity : widget.size,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.imagens.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, index) {
                return FutureBuilder<String?>(
                  future: _resolveUrl(widget.imagens[index]),
                  builder: (context, snap) {
                    final url = snap.data;

                    if (snap.connectionState != ConnectionState.done) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    if (url == null || url.isEmpty) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined),
                      );
                    }

                    return Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          if (widget.imagens.length > 1 && _index > 0)
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: botaoSeta(
                  icon: Icons.arrow_back_ios,
                  onTap: () {
                    _controller.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.ease,
                    );
                  },
                ),
              ),
            ),
          if (widget.imagens.length > 1 && _index < widget.imagens.length - 1)
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: botaoSeta(
                  icon: Icons.arrow_forward_ios,
                  onTap: () {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.ease,
                    );
                  },
                ),
              ),
            ),
          if (widget.imagens.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imagens.length, (i) {
                  return Container(
                    width: i == _index ? 16 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _index ? Colors.white : Colors.white70,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormaEntregaCatalogo {
  final String id;
  final String tipo;
  final String nome;
  final String descricao;
  final String prazo;
  final double valor;

  const _FormaEntregaCatalogo({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.descricao,
    required this.prazo,
    required this.valor,
  });
}

class _ItemCarrinho {
  final String id;
  final String tipo;
  final String nome;
  int quantidade;
  final double valorUnitario;
  final String? imagemUrl;

  _ItemCarrinho({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.quantidade,
    required this.valorUnitario,
    this.imagemUrl,
  });

  double get total => quantidade * valorUnitario;

  String get tipoLabel {
    if (tipo == 'produto') return 'Produto';
    if (tipo == 'servico') return 'Serviço';
    return tipo;
  }
}

class _CatalogoItemDoc {
  final String id;
  final String tipo;
  final Map<String, dynamic> data;

  const _CatalogoItemDoc({
    required this.id,
    required this.tipo,
    required this.data,
  });
}
