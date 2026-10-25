import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting('id_ID', null).catchError((e) {
    print("Error init date format: $e");
  });
  runApp(const WarungBarokahApp());
}

class WarungBarokahApp extends StatelessWidget {
  const WarungBarokahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warung Barokah Kiarajangkung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class Product {
  String id;
  String name;
  String category;
  double buyPrice;
  double price;
  int stock;
  String retailName;
  int retailConversion;
  double retailPrice;
  String barcode;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.buyPrice,
    required this.price,
    required this.stock,
    this.retailName = '',
    this.retailConversion = 1,
    this.retailPrice = 0,
    this.barcode = '',
  });

  bool get hasRetail => retailName.isNotEmpty && retailConversion > 1 && retailPrice > 0;

  String getFormattedStock() {
    if (!hasRetail) return '$stock Pcs';
    int mainUnit = stock ~/ retailConversion;
    int remainder = stock % retailConversion;
    if (remainder == 0) {
      return '$mainUnit Unit Utama ($stock)';
    }
    return '$mainUnit Unit + $remainder $retailName ($stock Total)';
  }
}

class CartItem {
  Product product;
  int quantity;
  bool isRetail;

  CartItem({required this.product, required this.quantity, this.isRetail = false});

  double get unitPrice => isRetail ? product.retailPrice : product.price;
  double get totalPrice => unitPrice * quantity;
  
  double get totalBuyPrice {
    if (isRetail) {
      double buyPerSmallUnit = product.buyPrice / product.retailConversion;
      return buyPerSmallUnit * quantity;
    } else {
      return product.buyPrice * quantity;
    }
  }

  int get stockDeduction => isRetail ? quantity : (quantity * product.retailConversion);
}

class TransactionRecord {
  String id;
  DateTime date;
  List<CartItem> items;
  double subtotal;
  double discount;
  double tax;
  double total;
  double payAmount;
  double change;
  double customNetProfit;
  String itemsSummary;
  String staffName;
  String paymentType;

  TransactionRecord({
    required this.id,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.payAmount,
    required this.change,
    this.customNetProfit = 0,
    this.itemsSummary = '',
    this.staffName = '-',
    this.paymentType = 'Tunai',
  });

  double get totalCapital => items.fold(0, (sum, item) => sum + item.totalBuyPrice);
  double get netProfit => items.isNotEmpty ? ((subtotal - discount) - totalCapital) : customNetProfit;
}

class DebtRecord {
  String id;
  String customerName;
  String staffName;
  DateTime date;
  double totalAmount;
  double paidAmount;
  double remainingAmount;
  String status;
  String itemsSummary;
  String settlementHistory;

  DebtRecord({
    required this.id,
    required this.customerName,
    required this.staffName,
    required this.date,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    required this.itemsSummary,
    this.settlementHistory = '',
  });
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  List<Product> products = [];
  List<CartItem> cart = [];
  List<TransactionRecord> transactions = [];
  List<DebtRecord> debts = [];

  TextEditingController searchKasirController = TextEditingController();
  String searchKasirQuery = '';
  String selectedCategory = 'Semua';

  TextEditingController searchMasterController = TextEditingController();
  String searchMasterQuery = '';
  String productSortOption = 'Default';

  final AudioPlayer audioPlayer = AudioPlayer();

  final String googleSheetUrl =
      'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec';

  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      fetchAllDataFromGoogleSheets();
    });
  }

  void fetchAllDataFromGoogleSheets() {
    fetchProductsFromGoogleSheets();
    fetchTransactionsFromGoogleSheets();
    fetchDebtsFromGoogleSheets();
  }

  Future<void> fetchProductsFromGoogleSheets() async {
    try {
      final response = await http.get(Uri.parse(googleSheetUrl));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            products = data
                .map((item) => Product(
                      id: item['id'].toString(),
                      name: item['name'] ?? '',
                      category: item['category'] ?? 'Umum',
                      buyPrice: (item['buyPrice'] as num?)?.toDouble() ?? 0,
                      price: (item['price'] as num?)?.toDouble() ?? 0,
                      stock: (item['stock'] as num?)?.toInt() ?? 0,
                      retailName: item['retailName'] ?? '',
                      retailConversion: (item['retailConversion'] as num?)?.toInt() ?? 1,
                      retailPrice: (item['retailPrice'] as num?)?.toDouble() ?? 0,
                      barcode: item['barcode'] ?? '',
                    ))
                .toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat produk: $e");
    }
  }

  Future<void> fetchTransactionsFromGoogleSheets() async {
    try {
      final response =
          await http.get(Uri.parse('$googleSheetUrl?action=getTransactions'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            transactions = data.map((item) {
              DateTime parsedDate;
              try {
                parsedDate = DateTime.parse(item['date'].toString());
              } catch (_) {
                parsedDate = DateTime.now();
              }
              return TransactionRecord(
                id: item['id'].toString(),
                date: parsedDate,
                items: [],
                subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0,
                discount: (item['discount'] as num?)?.toDouble() ?? 0,
                tax: (item['tax'] as num?)?.toDouble() ?? 0,
                total: (item['total'] as num?)?.toDouble() ?? 0,
                payAmount: (item['total'] as num?)?.toDouble() ?? 0,
                change: 0,
                customNetProfit: (item['netProfit'] as num?)?.toDouble() ?? 0,
                itemsSummary: item['itemsSummary'] ?? '',
                staffName: item['staffName'] ?? '-',
                paymentType: item['paymentType'] ?? 'Tunai',
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat transaksi: $e");
    }
  }

  Future<void> fetchDebtsFromGoogleSheets() async {
    try {
      final response =
          await http.get(Uri.parse('$googleSheetUrl?action=getDebts'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            debts = data.map((item) {
              DateTime parsedDate;
              try {
                parsedDate = DateTime.parse(item['date'].toString());
              } catch (_) {
                parsedDate = DateTime.now();
              }
              return DebtRecord(
                id: item['id'].toString(),
                customerName: item['customerName'] ?? '-',
                staffName: item['staffName'] ?? '-',
                date: parsedDate,
                totalAmount: (item['totalAmount'] as num?)?.toDouble() ?? 0,
                paidAmount: (item['paidAmount'] as num?)?.toDouble() ?? 0,
                remainingAmount:
                    (item['remainingAmount'] as num?)?.toDouble() ?? 0,
                status: item['status'] ?? 'Belum Lunas',
                itemsSummary: item['itemsSummary'] ?? '',
                settlementHistory: item['settlementHistory'] ?? '',
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat kasbon: $e");
    }
  }

  Future<void> saveProductToGoogleSheets(Product product) async {
    try {
      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveProduct",
          "id": product.id,
          "name": product.name,
          "category": product.category,
          "buyPrice": product.buyPrice,
          "price": product.price,
          "stock": product.stock,
          "retailName": product.retailName,
          "retailConversion": product.retailConversion,
          "retailPrice": product.retailPrice,
          "barcode": product.barcode,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan produk: $e");
    }
  }

  Future<void> saveTransactionToGoogleSheets(TransactionRecord trx) async {
    try {
      String itemsSummary = trx.items
          .map((i) => "${i.product.name} (${i.quantity}${i.isRetail ? i.product.retailName : ' Unit'})")
          .join(", ");

      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveTransaction",
          "id": trx.id,
          "date": DateFormat('yyyy-MM-dd HH:mm:ss').format(trx.date),
          "subtotal": trx.subtotal,
          "discount": trx.discount,
          "tax": trx.tax,
          "total": trx.total,
          "netProfit": trx.netProfit,
          "itemsSummary": itemsSummary,
          "staffName": trx.staffName,
          "paymentType": trx.paymentType,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan transaksi: $e");
    }
  }

  Future<void> saveDebtToGoogleSheets(DebtRecord debt) async {
    try {
      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveDebt",
          "id": debt.id,
          "customerName": debt.customerName,
          "staffName": debt.staffName,
          "date": DateFormat('yyyy-MM-dd HH:mm:ss').format(debt.date),
          "totalAmount": debt.totalAmount,
          "paidAmount": debt.paidAmount,
          "remainingAmount": debt.remainingAmount,
          "status": debt.status,
          "itemsSummary": debt.itemsSummary,
          "settlementHistory": debt.settlementHistory,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan kasbon: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      buildKasirPage(),
      buildProductManagementPage(),
      buildDebtPage(),
      buildHistoryPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.store, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Warung Barokah',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text('Kiarajangkung',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              fetchAllDataFromGoogleSheets();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memperbarui data...')),
              );
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Kasir'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Produk/Stok'),
          BottomNavigationBarItem(icon: Icon(Icons.book_online), label: 'Kasbon'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Laporan'),
        ],
      ),
    );
  }

  List<String> getCategories() {
    Set<String> categories = {'Semua'};
    for (var p in products) {
      if (p.category.isNotEmpty) categories.add(p.category);
    }
    return categories.toList();
  }

  // ================= 1. HALAMAN KASIR =================
  Widget buildKasirPage() {
    double subtotal = cart.fold(0, (sum, item) => sum + item.totalPrice);
    List<String> categories = getCategories();

    List<Product> filteredProducts = products.where((prod) {
      bool matchesSearch = prod.name.toLowerCase().contains(searchKasirQuery.toLowerCase()) ||
          prod.barcode.toLowerCase().contains(searchKasirQuery.toLowerCase());
      bool matchesCategory = selectedCategory == 'Semua' || prod.category == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchKasirController,
                  decoration: InputDecoration(
                    hintText: 'Cari produk / barcode...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchKasirQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                searchKasirController.clear();
                                searchKasirQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                  ),
                  onChanged: (value) => setState(() => searchKasirQuery = value),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final scannedCode = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
                  );
                  if (scannedCode != null && scannedCode.toString().isNotEmpty) {
                    processScannedBarcode(scannedCode.toString());
                  }
                },
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: const Text('Scan'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              String cat = categories[index];
              bool isSelected = selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (bool selected) => setState(() => selectedCategory = cat),
                  selectedColor: Colors.green[200],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 2,
          child: filteredProducts.isEmpty
              ? const Center(child: Text('Produk tidak ditemukan'))
              : ListView.builder(
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final prod = filteredProducts[index];
                    return ListTile(
                      title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Jual: ${currencyFormatter.format(prod.price)} | Stok: ${prod.getFormattedStock()}'),
                      trailing: ElevatedButton(
                        onPressed: prod.stock > 0 ? () => handleAddToCart(prod) : null,
                        child: const Text('Tambah'),
                      ),
                    );
                  },
                ),
        ),
        const Divider(thickness: 2),
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[100],
            child: cart.isEmpty
                ? const Center(child: Text('Keranjang Masih Kosong'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      String unitLabel = item.isRetail ? item.product.retailName : 'Utama';
                      return ListTile(
                        title: Text('${item.product.name} ($unitLabel)'),
                        subtitle: Text(
                            '${item.quantity} x ${currencyFormatter.format(item.unitPrice)} = ${currencyFormatter.format(item.totalPrice)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  if (item.quantity > 1) {
                                    item.quantity--;
                                  } else {
                                    cart.removeAt(index);
                                  }
                                });
                              },
                            ),
                            Text('${item.quantity}', style: const TextStyle(fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.green),
                              onPressed: () {
                                setState(() {
                                  int currentDeduction = item.isRetail ? (item.quantity + 1) : ((item.quantity + 1) * item.product.retailConversion);
                                  if (currentDeduction <= item.product.stock) {
                                    item.quantity++;
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Stok tidak mencukupi!')));
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subtotal Belanja:', style: TextStyle(fontSize: 12)),
                  Text(
                    currencyFormatter.format(subtotal),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green[800]),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: cart.isEmpty ? null : () => showPaymentDialog(subtotal),
                child: const Text('PROSES BAYAR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        )
      ],
    );
  }

  void processScannedBarcode(String code) async {
    try {
      final matchingProduct = products.firstWhere(
        (p) => p.barcode == code || p.id == code,
      );

      await audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/submarines/sonar_ping.ogg'));
      HapticFeedback.mediumImpact();

      handleAddToCart(matchingProduct);
    } catch (_) {
      await audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'));
      HapticFeedback.vibrate();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('Barcode "$code" belum terdaftar!'),
          action: SnackBarAction(
            label: '+ Tambah Produk',
            textColor: Colors.amberAccent,
            onPressed: () {
              setState(() => _currentIndex = 1);
              showProductDialog(null, initialBarcode: code);
            },
          ),
        ),
      );
    }
  }

  void handleAddToCart(Product prod) {
    if (!prod.hasRetail) {
      addItemToCart(prod, 1, false);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pilih Satuan - ${prod.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory, color: Colors.green),
              title: const Text('Satuan Utama'),
              subtitle: Text('Harga: ${currencyFormatter.format(prod.price)}'),
              onTap: () {
                Navigator.pop(context);
                addItemToCart(prod, 1, false);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.storefront, color: Colors.blue),
              title: Text('Satuan Eceran (${prod.retailName})'),
              subtitle: Text('Harga: ${currencyFormatter.format(prod.retailPrice)}'),
              onTap: () {
                Navigator.pop(context);
                addItemToCart(prod, 1, true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void addItemToCart(Product prod, int qty, bool isRetail) {
    setState(() {
      int requiredStock = isRetail ? qty : (qty * prod.retailConversion);
      int existingIndex = cart.indexWhere((c) => c.product.id == prod.id && c.isRetail == isRetail);
      
      if (existingIndex != -1) {
        int newQty = cart[existingIndex].quantity + qty;
        int totalRequired = isRetail ? newQty : (newQty * prod.retailConversion);
        if (totalRequired <= prod.stock) {
          cart[existingIndex].quantity = newQty;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok tidak cukup!')));
        }
      } else {
        if (requiredStock <= prod.stock) {
          cart.add(CartItem(product: prod, quantity: qty, isRetail: isRetail));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok tidak cukup!')));
        }
      }
    });
  }

  void showPaymentDialog(double subtotal) {
    TextEditingController discountCtrl = TextEditingController(text: '0');
    TextEditingController taxPercentCtrl = TextEditingController(text: '0');
    TextEditingController payCtrl = TextEditingController();
    TextEditingController customerNameCtrl = TextEditingController();
    TextEditingController staffNameCtrl = TextEditingController();
    
    // Variabel untuk Split Bill
    TextEditingController splitCashCtrl = TextEditingController(text: '0');
    TextEditingController splitQrisCtrl = TextEditingController(text: '0');

    String paymentType = 'Tunai';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double discount = double.tryParse(discountCtrl.text) ?? 0;
            double taxPercent = double.tryParse(taxPercentCtrl.text) ?? 0;
            double taxAmount = (subtotal - discount) * (taxPercent / 100);
            double grandTotal = (subtotal - discount) + taxAmount;

            double payAmount = double.tryParse(payCtrl.text) ?? 0;
            if (paymentType == 'Kasbon Penuh') payAmount = 0;
            
            double remainingDebt = paymentType != 'Tunai' && paymentType != 'QRIS' 
                ? (grandTotal - payAmount > 0 ? grandTotal - payAmount : 0) 
                : 0;

            // Perhitungan Split Bill
            double splitCash = double.tryParse(splitCashCtrl.text) ?? 0;
            double splitQris = double.tryParse(splitQrisCtrl.text) ?? 0;
            double splitRemaining = grandTotal - (splitCash + splitQris);

            return AlertDialog(
              title: const Text('Pembayaran & Metode'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: staffNameCtrl,
                      decoration: const InputDecoration(labelText: 'Nama Kasir *', prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: paymentType,
                      decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'Tunai', child: Text('💵 Tunai / Lunas')),
                        DropdownMenuItem(value: 'QRIS', child: Text('📱 QRIS (Non-Tunai)')),
                        DropdownMenuItem(value: 'Split Bill', child: Text('🔀 Split Bill (Tunai + QRIS)')),
                        DropdownMenuItem(value: 'Kasbon Penuh', child: Text('🔴 Kasbon Penuh (Rp 0)')),
                        DropdownMenuItem(value: 'Kasbon Sebagian', child: Text('🟡 Bayar Sebagian (DP)')),
                      ],
                      onChanged: (val) => setDialogState(() {
                        paymentType = val!;
                        if (paymentType == 'Kasbon Penuh') payCtrl.text = '0';
                        if (paymentType == 'QRIS') payCtrl.text = grandTotal.toString();
                      }),
                    ),
                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customerNameCtrl,
                        decoration: const InputDecoration(labelText: 'Nama Pengutang / Pelanggan *', prefixIcon: Icon(Icons.badge), border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                    const Divider(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal:'), Text(currencyFormatter.format(subtotal))]),
                    const SizedBox(height: 6),
                    TextField(controller: discountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diskon (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true), onChanged: (val) => setDialogState(() {})),
                    const SizedBox(height: 6),
                    TextField(controller: taxPercentCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PPN (%)', suffixText: '%', border: OutlineInputBorder(), isDense: true), onChanged: (val) => setDialogState(() {})),
                    const Divider(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL BELANJA:', style: TextStyle(fontWeight: FontWeight.bold)), Text(currencyFormatter.format(grandTotal), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[850]))]),
                    
                    // TAMPILAN JIKA PILIH QRIS (Menampilkan Simulasi Barcode QRIS)
                    if (paymentType == 'QRIS') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                        child: Column(
                          children: [
                            const Text('Scan QRIS Warung Barokah', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 8),
                            Container(
                              width: 140,
                              height: 140,
                              color: Colors.white,
                              child: const Center(
                                child: Icon(Icons.qr_code_2, size: 120, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Nominal: ${currencyFormatter.format(grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                      )
                    ],

                    // TAMPILAN JIKA PILIH SPLIT BILL
                    if (paymentType == 'Split Bill') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pengaturan Split Bill (Bagi Tagihan):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: splitCashCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Bayar Tunai (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true),
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: splitQrisCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Bayar QRIS (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true),
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Kurang / Sisa:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                Text(currencyFormatter.format(splitRemaining), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: splitRemaining == 0 ? Colors.green : Colors.red)),
                              ],
                            )
                          ],
                        ),
                      )
                    ],

                    if (paymentType != 'Kasbon Penuh' && paymentType != 'QRIS' && paymentType != 'Split Bill') ...[
                      const SizedBox(height: 10),
                      TextField(controller: payCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: paymentType == 'Kasbon Sebagian' ? 'Uang DP' : 'Uang Diterima', prefixText: 'Rp ', border: const OutlineInputBorder()), onChanged: (val) => setDialogState(() {})),
                    ],
                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.red[50],
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sisa Utang:', style: TextStyle(color: Colors.red)), Text(currencyFormatter.format(remainingDebt), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                      )
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () {
                    if (staffNameCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi Nama Kasir!')));
                      return;
                    }
                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill' && customerNameCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi Nama Pengutang!')));
                      return;
                    }
                    if (paymentType == 'Tunai' && payAmount < grandTotal) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uang pembayaran kurang!')));
                      return;
                    }
                    if (paymentType == 'Split Bill' && splitRemaining > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Total pembayaran Split Bill belum lunas!')));
                      return;
                    }

                    double finalPaid = paymentType == 'QRIS' ? grandTotal : (paymentType == 'Split Bill' ? (splitCash + splitQris) : payAmount);
                    double kembalian = (paymentType == 'Tunai') ? finalPaid - grandTotal : 0;
                    if (paymentType == 'Split Bill' && (splitCash + splitQris) > grandTotal) {
                      kembalian = (splitCash + splitQris) - grandTotal;
                    }

                    for (var item in cart) {
                      item.product.stock -= item.stockDeduction;
                      saveProductToGoogleSheets(item.product);
                    }

                    String summary = cart.map((i) => "${i.product.name} (${i.quantity}${i.isRetail ? i.product.retailName : 'x'})").join(", ");
                    String finalPaymentLabel = paymentType == 'Split Bill' ? 'Split Bill (Tunai+QRIS)' : paymentType;

                    TransactionRecord trx = TransactionRecord(
                      id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                      date: DateTime.now(),
                      items: List.from(cart),
                      subtotal: subtotal,
                      discount: discount,
                      tax: taxAmount,
                      total: grandTotal,
                      payAmount: finalPaid,
                      change: kembalian,
                      staffName: staffNameCtrl.text,
                      paymentType: finalPaymentLabel,
                      itemsSummary: summary,
                    );

                    saveTransactionToGoogleSheets(trx);
                    transactions.add(trx);

                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill') {
                      DebtRecord newDebt = DebtRecord(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        customerName: customerNameCtrl.text,
                        staffName: staffNameCtrl.text,
                        date: DateTime.now(),
                        totalAmount: grandTotal,
                        paidAmount: finalPaid,
                        remainingAmount: remainingDebt,
                        status: 'Belum Lunas',
                        itemsSummary: summary,
                        settlementHistory: finalPaid > 0 ? "${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}: DP ${currencyFormatter.format(finalPaid)} (${staffNameCtrl.text})\n" : "",
                      );
                      saveDebtToGoogleSheets(newDebt);
                      debts.add(newDebt);
                    }

                    setState(() => cart.clear());
                    Navigator.pop(context);
                    showReceiptDialog(trx);
                  },
                  child: const Text('SIMPAN & NOTA'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= 2. HALAMAN MANAJEMEN PRODUK & BARCODE =================
  Widget buildProductManagementPage() {
    Map<String, int> salesCount = {};
    for (var trx in transactions) {
      for (var item in trx.items) {
        salesCount[item.product.id] = (salesCount[item.product.id] ?? 0) + item.stockDeduction;
      }
    }

    List<Product> filteredMasterProducts = products.where((prod) {
      bool matchesSearch = prod.name.toLowerCase().contains(searchMasterQuery.toLowerCase()) ||
          prod.barcode.toLowerCase().contains(searchMasterQuery.toLowerCase());
      if (productSortOption == 'Stok Kosong') return matchesSearch && prod.stock == 0;
      if (productSortOption == 'Stok Menipis') return matchesSearch && prod.stock > 0 && prod.stock < (prod.retailConversion > 1 ? prod.retailConversion : 5);
      return matchesSearch;
    }).toList();

    filteredMasterProducts.sort((a, b) {
      if (productSortOption == 'Stok Terkecil') return a.stock.compareTo(b.stock);
      if (productSortOption == 'Stok Terbesar') return b.stock.compareTo(a.stock);
      if (productSortOption == 'Paling Laku') return (salesCount[b.id] ?? 0).compareTo(salesCount[a.id] ?? 0);
      return a.name.compareTo(b.name);
    });

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green[700],
        onPressed: () => showProductDialog(null),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchMasterController,
                    decoration: InputDecoration(
                      hintText: 'Cari stok / barcode...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchMasterQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { searchMasterController.clear(); searchMasterQuery = ''; })) : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    ),
                    onChanged: (val) => setState(() => searchMasterQuery = val),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                  child: DropdownButton<String>(
                    value: productSortOption,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'Default', child: Text('Urut: Default')),
                      DropdownMenuItem(value: 'Stok Kosong', child: Text('🔴 Stok Kosong')),
                      DropdownMenuItem(value: 'Stok Menipis', child: Text('🟡 Stok Menipis')),
                      DropdownMenuItem(value: 'Stok Terkecil', child: Text('Stok Terkecil')),
                      DropdownMenuItem(value: 'Stok Terbesar', child: Text('Stok Terbesar')),
                      DropdownMenuItem(value: 'Paling Laku', child: Text('Paling Laku')),
                    ],
                    onChanged: (val) => setState(() => productSortOption = val!),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredMasterProducts.isEmpty
                ? const Center(child: Text('Barang tidak ditemukan'))
                : ListView.builder(
                    itemCount: filteredMasterProducts.length,
                    itemBuilder: (context, index) {
                      final prod = filteredMasterProducts[index];
                      Color stockColor = prod.stock == 0 ? Colors.red : (prod.stock < 10 ? Colors.amber[700]! : Colors.green);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: stockColor,
                            child: Text('${prod.stock}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                          title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'Kategori: ${prod.category} | Barcode: ${prod.barcode.isNotEmpty ? prod.barcode : "-"}\nStok: ${prod.getFormattedStock()}${prod.hasRetail ? ' | Eceran: ${prod.retailName}' : ''}'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => showProductDialog(prod)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => products.removeWhere((p) => p.id == prod.id))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void showProductDialog(Product? product, {String? initialBarcode}) {
    bool isEdit = product != null;
    TextEditingController nameCtrl = TextEditingController(text: isEdit ? product.name : '');
    TextEditingController categoryCtrl = TextEditingController(text: isEdit ? product.category : '');
    TextEditingController buyPriceCtrl = TextEditingController(text: isEdit ? product.buyPrice.toInt().toString() : '');
    TextEditingController priceCtrl = TextEditingController(text: isEdit ? product.price.toInt().toString() : '');
    TextEditingController stockCtrl = TextEditingController(text: isEdit ? product.stock.toString() : '');
    TextEditingController barcodeCtrl = TextEditingController(
      text: isEdit ? product.barcode : (initialBarcode ?? ''),
    );
    
    TextEditingController retailNameCtrl = TextEditingController(text: isEdit ? product.retailName : '');
    TextEditingController retailConvCtrl = TextEditingController(text: isEdit ? product.retailConversion.toString() : '1');
    TextEditingController retailPriceCtrl = TextEditingController(text: isEdit ? product.retailPrice.toInt().toString() : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Produk & Barcode' : 'Tambah Produk Baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Barang *')),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Kategori')),
              Row(
                children: [
                  Expanded(child: TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Kode Barcode'))),
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.green),
                    tooltip: 'Scan Barcode',
                    onPressed: () async {
                      final scanned = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
                      );
                      if (scanned != null) {
                        barcodeCtrl.text = scanned.toString();
                      }
                    },
                  ),
                ],
              ),
              TextField(controller: buyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Modal Satuan Utama (Rp)')),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual Satuan Utama (Rp)')),
              TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok (Satuan Terkecil)')),
              const Divider(height: 20),
              const Text('--- PENGATURAN ECERAN ---', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
              TextField(controller: retailNameCtrl, decoration: const InputDecoration(labelText: 'Nama Satuan Eceran (Cth: Batang)')),
              TextField(controller: retailConvCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Isi per Utama (Cth: 12)')),
              TextField(controller: retailPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual Eceran (Rp)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                Product newProd = Product(
                  id: isEdit ? product.id : DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text,
                  category: categoryCtrl.text.isEmpty ? 'Umum' : categoryCtrl.text,
                  buyPrice: double.tryParse(buyPriceCtrl.text) ?? 0,
                  price: double.tryParse(priceCtrl.text) ?? 0,
                  stock: int.tryParse(stockCtrl.text) ?? 0,
                  retailName: retailNameCtrl.text,
                  retailConversion: int.tryParse(retailConvCtrl.text) ?? 1,
                  retailPrice: double.tryParse(retailPriceCtrl.text) ?? 0,
                  barcode: barcodeCtrl.text,
                );
                setState(() {
                  if (isEdit) {
                    int idx = products.indexWhere((p) => p.id == product.id);
                    if (idx != -1) products[idx] = newProd;
                  } else {
                    products.add(newProd);
                  }
                });
                saveProductToGoogleSheets(newProd);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk berhasil disimpan!')));
              }
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  // ================= 3. HALAMAN KASBON / PIUTANG KELOMPOK =================
  Widget buildDebtPage() {
    Map<String, List<DebtRecord>> groupedDebts = {};
    for (var d in debts) {
      String nameKey = d.customerName.trim().toUpperCase();
      if (!groupedDebts.containsKey(nameKey)) {
        groupedDebts[nameKey] = [];
      }
      groupedDebts[nameKey]!.add(d);
    }

    double totalActiveDebts = debts.where((d) => d.status != 'Lunas').fold(0, (sum, d) => sum + d.remainingAmount);

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
            child: Column(
              children: [
                const Text('Total Sisa Piutang Warung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(currencyFormatter.format(totalActiveDebts), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red[800])),
              ],
            ),
          ),
          Expanded(
            child: groupedDebts.isEmpty
                ? const Center(child: Text('Belum ada data kasbon.'))
                : ListView.builder(
                    itemCount: groupedDebts.keys.length,
                    itemBuilder: (context, index) {
                      String custName = groupedDebts.keys.elementAt(index);
                      List<DebtRecord> custDebts = groupedDebts[custName]!;
                      
                      double custTotalDebt = custDebts.where((d) => d.status != 'Lunas').fold(0, (sum, d) => sum + d.remainingAmount);
                      bool isAllLunas = custTotalDebt == 0;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: isAllLunas ? Colors.green : Colors.red,
                            child: Icon(isAllLunas ? Icons.check : Icons.person, color: Colors.white),
                          ),
                          title: Text(custName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text('Sisa Utang: ${currencyFormatter.format(custTotalDebt)} (${custDebts.length} Nota Kasbon)',
                              style: TextStyle(color: isAllLunas ? Colors.green[700] : Colors.red[700], fontWeight: FontWeight.w500)),
                          children: [
                            Container(
                              color: Colors.grey[50],
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('--- RINCIAN PIUTANG PELANGGAN ---', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  ...custDebts.map((d) => Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('📅 ${DateFormat('dd/MM/yyyy HH:mm').format(d.date)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                Text(d.status, style: TextStyle(color: d.status == 'Lunas' ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                                              ],
                                            ),
                                            Text('Kasir: ${d.staffName}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                            const Divider(height: 12),
                                            Text('Barang:\n${d.itemsSummary}', style: const TextStyle(fontSize: 12)),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('Total Nota: ${currencyFormatter.format(d.totalAmount)}', style: const TextStyle(fontSize: 11)),
                                                Text('Sisa: ${currencyFormatter.format(d.remainingAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 11)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      if (!isAllLunas)
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: () => showGroupSettlementDialog(custName, custDebts, custTotalDebt),
                                          icon: const Icon(Icons.payment, size: 16),
                                          label: const Text('Bayar Cicil/Lunas'),
                                        ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                        onPressed: () => generateAndSharePDF(custName, custDebts, custTotalDebt),
                                        icon: const Icon(Icons.share, size: 16),
                                        label: const Text('Kirim PDF WA'),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void showGroupSettlementDialog(String custName, List<DebtRecord> custDebts, double totalDebt) {
    TextEditingController payCtrl = TextEditingController();
    TextEditingController staffCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pelunasan Utang - $custName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total Sisa Utang: ${currencyFormatter.format(totalDebt)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 12),
            TextField(controller: staffCtrl, decoration: const InputDecoration(labelText: 'Nama Kasir Penerima *', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: payCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah Pembayaran (Rp)', prefixText: 'Rp ', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (staffCtrl.text.isEmpty) return;
              double payAmount = double.tryParse(payCtrl.text) ?? 0;
              if (payAmount <= 0) return;

              double remainingPay = payAmount;

              setState(() {
                for (var d in custDebts) {
                  if (d.status != 'Lunas' && remainingPay > 0) {
                    if (remainingPay >= d.remainingAmount) {
                      remainingPay -= d.remainingAmount;
                      d.paidAmount += d.remainingAmount;
                      d.remainingAmount = 0;
                      d.status = 'Lunas';
                    } else {
                      d.paidAmount += remainingPay;
                      d.remainingAmount -= remainingPay;
                      remainingPay = 0;
                    }
                    d.settlementHistory += "${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}: Bayar ${currencyFormatter.format(payAmount)} (${staffCtrl.text})\n";
                    saveDebtToGoogleSheets(d);
                  }
                }
              });

              TransactionRecord settlementTrx = TransactionRecord(
                id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                date: DateTime.now(),
                items: [],
                subtotal: payAmount,
                discount: 0,
                tax: 0,
                total: payAmount,
                payAmount: payAmount,
                change: 0,
                customNetProfit: payAmount,
                itemsSummary: "Pelunasan Piutang: $custName",
                staffName: staffCtrl.text,
                paymentType: 'Pelunasan Kasbon',
              );
              saveTransactionToGoogleSheets(settlementTrx);
              transactions.add(settlementTrx);

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran berhasil dicatat!')));
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  Future<void> generateAndSharePDF(String custName, List<DebtRecord> custDebts, double totalDebt) async {
    final pdf = pw.Document();
    final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.08,
                  child: pw.Image(logoImage, width: 320, height: 320),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Image(logoImage, width: 50, height: 50),
                        pw.SizedBox(height: 4),
                        pw.Text('WARUNG BAROKAH KIARAJANGKUNG', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Sukahening, Tasikmalaya | Struk Piutang / Kasbon', style: const pw.TextStyle(fontSize: 10)),
                        pw.Divider(thickness: 1),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text('Rincian Piutang / Kasbon Pelanggan:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text('Nama Pelanggan: $custName', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Tanggal Cetak  : ${DateFormat('dd MMMM yyyy HH:mm', 'id_ID').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 12),
                  pw.Table.fromTextArray(
                    headers: ['Tanggal', 'Kasir', 'Rincian Barang', 'Total', 'Sisa Utang'],
                    data: custDebts.map((d) => [
                      DateFormat('dd/MM/yy HH:mm').format(d.date),
                      d.staffName,
                      d.itemsSummary,
                      currencyFormatter.format(d.totalAmount),
                      currencyFormatter.format(d.remainingAmount),
                    ]).toList(),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Divider(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL SISA PIUTANG:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.Text(currencyFormatter.format(totalDebt), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red)),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Center(child: pw.Text('Terima Kasih Atas Kepercayaannya!', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10))),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Nota_Piutang_$custName.pdf');
  }

  Future<void> generateAndShareTransactionPDF(TransactionRecord trx) async {
    final pdf = pw.Document();
    final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.10,
                  child: pw.Image(logoImage, width: 180, height: 180),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Image(logoImage, width: 40, height: 40),
                        pw.SizedBox(height: 2),
                        pw.Text('WARUNG BAROKAH', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text('KIARAJANGKUNG', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Sukahening, Tasikmalaya', style: const pw.TextStyle(fontSize: 8)),
                        pw.Divider(thickness: 1),
                      ],
                    ),
                  ),
                  pw.Text('No Nota : #${trx.id}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Tanggal : ${DateFormat('dd/MM/yy HH:mm').format(trx.date)}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Kasir   : ${trx.staffName}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Metode  : ${trx.paymentType}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Divider(thickness: 0.5),
                  if (trx.items.isNotEmpty)
                    ...trx.items.map((item) => pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('${item.product.name} (${item.quantity}${item.isRetail ? item.product.retailName : ''})', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text(currencyFormatter.format(item.totalPrice), style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ))
                  else
                    pw.Text('Items: ${trx.itemsSummary}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Divider(thickness: 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Belanja:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text(currencyFormatter.format(trx.total), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Bayar:', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(currencyFormatter.format(trx.payAmount), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Kembali:', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(currencyFormatter.format(trx.change), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Center(child: pw.Text('Terima Kasih Atas Kunjungan Anda!', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic))),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Struk_Nota_${trx.id}.pdf');
  }

  // ================= 4. HALAMAN LAPORAN =================
  Widget buildHistoryPage() {
    DateTime now = DateTime.now();

    double dailyOmsetCash = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day && t.paymentType != 'Kasbon Penuh').fold(0, (s, t) => s + t.payAmount);
    double dailyNewDebt = debts.where((d) => d.date.year == now.year && d.date.month == now.month && d.date.day == now.day).fold(0, (s, d) => s + d.remainingAmount);
    double dailyProfit = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day).fold(0, (s, t) => s + t.netProfit);
    int dailyCount = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day).length;

    double monthlyOmsetCash = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.paymentType != 'Kasbon Penuh').fold(0, (s, t) => s + t.payAmount);
    double monthlyProfit = transactions.where((t) => t.date.year == now.year && t.date.month == now.month).fold(0, (s, t) => s + t.netProfit);
    int monthlyCount = transactions.where((t) => t.date.year == now.year && t.date.month == now.month).length;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📅 Rekap Hari Ini (${DateFormat('dd MMM yyyy').format(now)})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900])),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [const Text('Uang Masuk', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(dailyOmsetCash), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[800]))]),
                    Column(children: [const Text('Piutang Baru', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(dailyNewDebt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red))]),
                    Column(children: [const Text('Laba Bersih', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(dailyProfit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue))]),
                  ],
                ),
                const SizedBox(height: 6),
                Center(child: Text('$dailyCount Aktivitas Transaksi', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic))),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📊 Rekap Bulan Ini (${DateFormat('MMMM yyyy', 'id_ID').format(now)})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [const Text('Total Uang Masuk', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(monthlyOmsetCash), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[800]))]),
                    Column(children: [const Text('Laba Bersih', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(monthlyProfit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue))]),
                  ],
                ),
                const SizedBox(height: 6),
                Center(child: Text('$monthlyCount Transaksi', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic))),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Align(alignment: Alignment.centerLeft, child: Text('Daftar Riwayat Penjualan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          ),
          transactions.isEmpty
              ? const Padding(padding: EdgeInsets.all(32.0), child: Center(child: Text('Belum ada transaksi')))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final trx = transactions[transactions.length - 1 - index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: ListTile(
                        title: Text('Nota #${trx.id} [${trx.paymentType}]'),
                        subtitle: Text('Tgl: ${DateFormat('dd/MM/yy HH:mm').format(trx.date)} | Kasir: ${trx.staffName}\nItem: ${trx.itemsSummary}'),
                        trailing: Text(currencyFormatter.format(trx.total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        onTap: () => showReceiptDialog(trx),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  void showReceiptDialog(TransactionRecord trx) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.08,
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo.png', width: 45, height: 45),
                  const SizedBox(height: 4),
                  const Text('WARUNG BAROKAH KIARAJANGKUNG', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Text('Kiarajangkung, Sukahening, Tasikmalaya', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
                  const Divider(),
                  Text('No: #${trx.id} | ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}\nKasir: ${trx.staffName} | Tipe: ${trx.paymentType}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                  const Divider(),
                  if (trx.items.isNotEmpty)
                    ...trx.items.map((item) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${item.product.name} (${item.quantity}${item.isRetail ? item.product.retailName : ''})', style: const TextStyle(fontSize: 12)),
                            Text(currencyFormatter.format(item.totalPrice), style: const TextStyle(fontSize: 12)),
                          ],
                        ))
                  else
                    Text('Rincian: ${trx.itemsSummary}', style: const TextStyle(fontSize: 11)),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total:'), Text(currencyFormatter.format(trx.total), style: const TextStyle(fontWeight: FontWeight.bold))]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Bayar:'), Text(currencyFormatter.format(trx.payAmount))]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Kembali:'), Text(currencyFormatter.format(trx.change))]),
                  const SizedBox(height: 10),
                  const Text('Terima Kasih!', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              printReceiptViaBluetooth(trx);
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Cetak Bluetooth'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              generateAndShareTransactionPDF(trx);
            },
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Kirim PDF WA'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> printReceiptViaBluetooth(TransactionRecord trx) async {
    try {
      List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) return;
      bool status = await PrintBluetoothThermal.connect(macPrinterAddress: devices.first.macAdress);
      if (status) {
        String receiptText = "       WARUNG BAROKAH\n       KIARAJANGKUNG\n--------------------------------\n"
            "No : #${trx.id}\nTgl: ${DateFormat('dd/MM/yy HH:mm').format(trx.date)}\nKasir: ${trx.staffName}\nTipe : ${trx.paymentType}\n--------------------------------\n";
        for (var item in trx.items) {
          receiptText += "${item.product.name} (${item.quantity}${item.isRetail ? item.product.retailName : ''})\n  = ${currencyFormatter.format(item.totalPrice)}\n";
        }
        receiptText += "--------------------------------\nTotal   : ${currencyFormatter.format(trx.total)}\nBayar   : ${currencyFormatter.format(trx.payAmount)}\nKembali : ${currencyFormatter.format(trx.change)}\n--------------------------------\n Terimakasih Atas Kunjungan Anda\n\n\n";
        await PrintBluetoothThermal.writeString(printText: PrintTextSize(size: 1, text: receiptText));
        await PrintBluetoothThermal.disconnect;
      }
    } catch (e) {
      print("Error cetak: $e");
    }
  }
}

class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode Produk'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }
}
