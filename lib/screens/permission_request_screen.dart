/// 权限请求管理界面
/// 展示和处理来自 OpenClaw 的权限请求
library;

import 'package:flutter/material.dart';
import '../services/permission_service.dart';
import '../widgets/common_widgets.dart';

class PermissionRequestScreen extends StatefulWidget {
  const PermissionRequestScreen({Key? key}) : super(key: key);

  @override
  State<PermissionRequestScreen> createState() =>
      _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> {
  final PermissionService _permissionService = PermissionService(
    // TODO: 注入 LocalStorageService
    throw UnimplementedError(),
  );

  List<PermissionRequest> _requests = [];
  bool _isLoading = true;
  PermissionStatus _filterStatus = PermissionStatus.pending;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final requests = await _permissionService.getAllRequests();
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  Future<void> _approveRequest(PermissionRequest request) async {
    try {
      await _permissionService.approvePermission(request.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 权限已批准')),
      );
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  Future<void> _rejectRequest(PermissionRequest request) async {
    try {
      await _permissionService.rejectPermission(request.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ 权限已拒绝')),
      );
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限请求管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选器
          _buildFilterBar(),
          
          // 请求列表
          Expanded(
            child: _isLoading
                ? const LoadingIndicator()
                : _buildRequestList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          const Text('状态筛选：', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: PermissionStatus.values.map((status) {
                  final isSelected = _filterStatus == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_getStatusText(status)),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _filterStatus = status);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestList() {
    final filteredRequests = _requests
        .where((r) => r.status == _filterStatus)
        .toList();

    if (filteredRequests.isEmpty) {
      return EmptyState(
        title: '暂无权限请求',
        icon: Icons.checklist,
        message: '暂无${_getStatusText(_filterStatus)}的权限请求',
      );
    }

    return ListView.separated(
      itemCount: filteredRequests.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return _buildRequestItem(filteredRequests[index]);
      },
    );
  }

  Widget _buildRequestItem(PermissionRequest request) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent 信息
            Row(
              children: [
                CircleAvatar(
                  child: Text(request.agentName[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.agentName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        request.agentId,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(request.status),
              ],
            ),

            const SizedBox(height: 16),

            // 权限类型
            _buildInfoRow(
              icon: Icons.security,
              label: '权限类型',
              value: _getPermissionTypeText(request.permissionType),
            ),

            const SizedBox(height: 8),

            // 请求原因
            _buildInfoRow(
              icon: Icons.description,
              label: '请求原因',
              value: request.reason,
            ),

            const SizedBox(height: 8),

            // 请求时间
            _buildInfoRow(
              icon: Icons.access_time,
              label: '请求时间',
              value: _formatDateTime(request.requestTime),
            ),

            if (request.expiryTime != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                icon: Icons.timer,
                label: '有效期至',
                value: _formatDateTime(request.expiryTime!),
              ),
            ],

            // 操作按钮
            if (request.status == PermissionStatus.pending) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text('拒绝'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => _showRejectDialog(request),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('批准'),
                    onPressed: () => _showApproveDialog(request),
                  ),
                ],
              ),
            ],

            if (request.status == PermissionStatus.approved) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.block, color: Colors.orange),
                    label: const Text('撤销'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange,
                    ),
                    onPressed: () => _showRevokeDialog(request),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(PermissionStatus status) {
    Color color;
    IconData icon;

    switch (status) {
      case PermissionStatus.pending:
        color = Colors.orange;
        icon = Icons.pending;
        break;
      case PermissionStatus.approved:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case PermissionStatus.rejected:
        color = Colors.red;
        icon = Icons.cancel;
        break;
      case PermissionStatus.expired:
        color = Colors.grey;
        icon = Icons.timer_off;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _getStatusText(status),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApproveDialog(PermissionRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批准权限'),
        content: Text(
          '确定要批准 ${request.agentName} 的 ${_getPermissionTypeText(request.permissionType)} 权限吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('批准'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _approveRequest(request);
    }
  }

  Future<void> _showRejectDialog(PermissionRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拒绝权限'),
        content: Text(
          '确定要拒绝 ${request.agentName} 的权限请求吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('拒绝'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _rejectRequest(request);
    }
  }

  Future<void> _showRevokeDialog(PermissionRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销权限'),
        content: Text(
          '确定要撤销 ${request.agentName} 的权限吗？撤销后该 Agent 将无法继续访问相关功能。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('撤销'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _permissionService.revokePermission(
        agentId: request.agentId,
        permissionType: request.permissionType,
      );
      _loadRequests();
    }
  }

  String _getStatusText(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.pending:
        return '待审批';
      case PermissionStatus.approved:
        return '已批准';
      case PermissionStatus.rejected:
        return '已拒绝';
      case PermissionStatus.expired:
        return '已过期';
    }
  }

  String _getPermissionTypeText(PermissionType type) {
    switch (type) {
      case PermissionType.initiateChat:
        return '发起聊天';
      case PermissionType.getAgentList:
        return '获取 Agent 列表';
      case PermissionType.getAgentCapabilities:
        return '获取 Agent 能力';
      case PermissionType.subscribeChannel:
        return '订阅 Channel';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
