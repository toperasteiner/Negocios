import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UsuariosUltimoAcessoScreen extends StatefulWidget {
  const UsuariosUltimoAcessoScreen({super.key});

  @override
  State<UsuariosUltimoAcessoScreen> createState() =>
      _UsuariosUltimoAcessoScreenState();
}

class _UsuariosUltimoAcessoScreenState
    extends State<UsuariosUltimoAcessoScreen> {
  String _filtroSelecionado = 'hoje';
  String _planoSelecionado = 'todos';

  final Map<String, String> _opcoesFiltro = {
    'hoje': 'Hoje',
    '7': 'Últimos 7 dias',
    '15': 'Últimos 15 dias',
    '30': 'Último mês',
  };

  final Map<String, String> _opcoesPlano = {
    'todos': 'Todos os planos',
    'free': 'Free',
    'starter': 'Starter',
    'premium': 'Premium',
  };

  DateTime _dataInicialFiltro() {
    final agora = DateTime.now();

    switch (_filtroSelecionado) {
      case 'hoje':
        return DateTime(agora.year, agora.month, agora.day);
      case '7':
        return agora.subtract(const Duration(days: 7));
      case '15':
        return agora.subtract(const Duration(days: 15));
      case '30':
        return agora.subtract(const Duration(days: 30));
      default:
        return DateTime(agora.year, agora.month, agora.day);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buscarUsuarios() {
    final dataInicial = _dataInicialFiltro();

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .where(
          'updatedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(dataInicial),
        );

    if (_planoSelecionado != 'todos') {
      query = query.where('planId', isEqualTo: _planoSelecionado);
    }

    return query.orderBy('updatedAt', descending: true).snapshots();
  }

  String _formatarData(dynamic valor) {
    if (valor == null) return 'Sem informação';

    if (valor is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(valor.toDate());
    }

    if (valor is DateTime) {
      return DateFormat('dd/MM/yyyy HH:mm').format(valor);
    }

    return 'Data inválida';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Último acesso dos usuários'),
        centerTitle: true,
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buscarUsuarios(),
        builder: (context, snapshot) {
          final carregando =
              snapshot.connectionState == ConnectionState.waiting;
          final usuarios = snapshot.data?.docs ?? [];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildFiltroUltimoAcesso(),

                const SizedBox(height: 10),

                _buildFiltroPlano(),

                const SizedBox(height: 16),

                _buildCardTotal(total: usuarios.length, carregando: carregando),

                const SizedBox(height: 16),

                Expanded(
                  child:
                      carregando
                          ? const Center(child: CircularProgressIndicator())
                          : usuarios.isEmpty
                          ? _buildVazio()
                          : ListView.separated(
                            itemCount: usuarios.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final data = usuarios[index].data();
                              return _buildCardUsuario(data);
                            },
                          ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFiltroUltimoAcesso() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filtroSelecionado,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items:
              _opcoesFiltro.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              _filtroSelecionado = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildFiltroPlano() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _planoSelecionado,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items:
              _opcoesPlano.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              _planoSelecionado = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCardTotal({required int total, required bool carregando}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.people_alt_outlined, color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total de usuários',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  carregando ? 'Carregando...' : total.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _descricaoFiltros(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _descricaoFiltros() {
    final periodo = _opcoesFiltro[_filtroSelecionado] ?? '';
    final plano = _opcoesPlano[_planoSelecionado] ?? '';

    return '$periodo • $plano';
  }

  Widget _buildCardUsuario(Map<String, dynamic> data) {
    final nome = data['displayName'] ?? data['nome'] ?? 'Sem nome';
    final email = data['email'] ?? 'Sem e-mail';
    final dataCadastro = _formatarData(data['createdAt']);
    final ultimoAcesso = _formatarData(data['updatedAt']);
    final plano = data['planId'] ?? data['plano'] ?? 'Sem plano';
    final ativo = data['active'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor:
                ativo ? const Color(0xFFE0ECFF) : Colors.grey.shade200,
            child: Icon(
              ativo ? Icons.person_outline : Icons.person_off_outlined,
              color: ativo ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome.toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  email.toString(),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.person_add_alt_1,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Cadastro: $dataCadastro',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Último acesso: $ultimoAcesso',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Text(
                  'Plano: $plano',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: ativo ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              ativo ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: ativo ? Colors.green.shade700 : Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Nenhum usuário encontrado',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Altere o filtro de último acesso ou plano.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
