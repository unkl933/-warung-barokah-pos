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
  double halfPrice;     
  double quarterPrice;  
  int stock;
  String retailName;
  int retailConversion;
  double retailPrice;
  String barcode;
  bool isConsignment;
  String salesName;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.buyPrice,
    required this.price,
    this.halfPrice = 0,
    this.quarterPrice = 0,
    required this.stock,
    this.retailName = '',
    this.retailConversion = 1,
    this.retailPrice = 0,
    this.barcode = '',
    this.isConsignment = false,
    this.salesName = '',
  });

  bool get hasRetail => retailName.isNotEmpty && retailConversion > 1 && retailPrice > 0;
  bool get hasHalfPrice => halfPrice > 0;
  bool get hasQuarterPrice => quarterPrice > 0;

  String getFormattedStock() {
    if (!hasRetail) return '$stock Pcs';
    int mainUnit = stock ~/ retailConversion;
    int remainder = stock % retailConversion;
    if (remainder == 0) {
      return '$mainUnit Unit Utama ($stock Total)';
    }
    return '$mainUnit Unit + $remainder $retailName ($stock Total)';
  }
}

enum CartUnitType { full, half, quarter, retail }

class CartItem {
  Product product;
  int quantity;
  CartUnitType unitType;

  CartItem({
    required this.product, 
    required this.quantity, 
    this.unitType = CartUnitType.full
  });

  double get unitPrice {
    switch (unitType) {
      case CartUnitType.quarter:
        return product.quarterPrice;
      case CartUnitType.half:
        return product.halfPrice;
      case CartUnitType.retail:
        return product.retailPrice;
      case CartUnitType.full:
      default:
        return product.price;
    }
  }

  double get totalPrice => unitPrice * quantity;
  
  double get totalBuyPrice {
    if (product.isConsignment) return 0;
    double buyPerSmallUnit = product.buyPrice / (product.retailConversion > 0 ? product.retailConversion : 1);
    return buyPerSmallUnit * stockDeduction;
  }

  int get stockDeduction {
    switch (unitType) {
      case CartUnitType.quarter:
        return quantity * (product.retailConversion ~/ 4);
      case CartUnitType.half:
        return quantity * (product.retailConversion ~/ 2);
      case CartUnitType.retail:
        return quantity;
      case CartUnitType.full:
      default:
        return quantity * product.retailConversion;
    }
  }

  String get unitLabel {
    switch (unitType) {
      case CartUnitType.quarter:
        return '1/4 Unit';
      case CartUnitType.half:
        return '1/2 Unit';
      case CartUnitType.retail:
        return product.retailName.isNotEmpty ? product.retailName : 'Eceran';
      case CartUnitType.full:
      default:
        return 'Utama';
    }
  }
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

  double get totalCapital {
    return items.fold(0, (sum, item) {
      if (item.product.isConsignment) {
        double buyPerSmallUnit = item.product.buyPrice / (item.product.retailConversion > 0 ? item.product.retailConversion : 1);
        return sum + (buyPerSmallUnit * item.stockDeduction);
      }
      return sum + item.totalBuyPrice;
    });
  }

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

  final TextEditingController searchKasirController = TextEditingController();
  String searchKasirQuery = '';
  String selectedCategory = 'Semua';

  final TextEditingController searchMasterController = TextEditingController();
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

  @override
  void dispose() {
    searchKasirController.dispose();
    searchMasterController.dispose();
    audioPlayer.dispose();
    super.dispose();
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
                      halfPrice: (item['halfPrice'] as num?)?.toDouble() ?? 0,
                      quarterPrice: (item['quarterPrice'] as num?)?.toDouble() ?? 0,
                      stock: (item['stock'] as num?)?.toInt() ?? 0,
                      retailName: item['retailName'] ?? '',
                      retailConversion: (item['retailConversion'] as num?)?.toInt() ?? 1,
                      retailPrice: (item['retailPrice'] as num?)?.toDouble() ?? 0,
                      barcode: item['barcode'] ?? '',
                      isConsignment: item['isConsignment'] == true || item['isConsignment'].toString() == 'true',
                      salesName: item['salesName'] ?? '',
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
          "halfPrice": product.halfPrice,
          "quarterPrice": product.quarterPrice,
          "stock": product.stock,
          "retailName": product.retailName,
          "retailConversion": product.retailConversion,
          "retailPrice": product.retailPrice,
          "barcode": product.barcode,
          "isConsignment": product.isConsignment,
          "salesName": product.salesName,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan produk: $e");
    }
  }

  Future<void> saveTransactionToGoogleSheets(TransactionRecord trx) async {
    try {
      String itemsSummary = trx.items
          .map((i) => "${i.product.name} (${i.quantity} ${i.unitLabel})")
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
      buildRestockPage(),
      buildConsignmentReportPage(),
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
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Produk'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag), label: 'Belanja'),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'Sales'),
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
                      return ListTile(
                        title: Text('${item.product.name} (${item.unitLabel})'),
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
                                  int nextQty = item.quantity + 1;
                                  int checkDeduction = 0;
                                  if (item.unitType == CartUnitType.quarter) {
                                    checkDeduction = nextQty * (item.product.retailConversion ~/ 4);
                                  } else if (item.unitType == CartUnitType.half) {
                                    checkDeduction = nextQty * (item.product.retailConversion ~/ 2);
                                  } else if (item.unitType == CartUnitType.retail) {
                                    checkDeduction = nextQty;
                                  } else {
                                    checkDeduction = nextQty * item.product.retailConversion;
                                  }

                                  if (checkDeduction <= item.product.stock) {
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
    if (!prod.hasRetail && !prod.hasHalfPrice && !prod.hasQuarterPrice) {
      addItemToCart(prod, 1, CartUnitType.full);
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
              title: const Text('Satuan Utuh (Bungkus/Pax)'),
              subtitle: Text('Harga: ${currencyFormatter.format(prod.price)}'),
              onTap: () {
                Navigator.pop(context);
                addItemToCart(prod, 1, CartUnitType.full);
              },
            ),
            if (prod.hasHalfPrice) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.pie_chart, color: Colors.orange),
                title: const Text('Setengah (1/2 Bungkus)'),
                subtitle: Text('Harga: ${currencyFormatter.format(prod.halfPrice)}'),
                onTap: () {
                  Navigator.pop(context);
                  addItemToCart(prod, 1, CartUnitType.half);
                },
              ),
            ],
            if (prod.hasQuarterPrice) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.donut_small, color: Colors.purple),
                title: const Text('Seperempat (1/4 Bungkus)'),
                subtitle: Text('Harga: ${currencyFormatter.format(prod.quarterPrice)}'),
                onTap: () {
                  Navigator.pop(context);
                  addItemToCart(prod, 1, CartUnitType.quarter);
                },
              ),
            ],
            if (prod.hasRetail) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.storefront, color: Colors.blue),
                title: Text('Satuan Eceran (${prod.retailName})'),
                subtitle: Text('Harga: ${currencyFormatter.format(prod.retailPrice)}'),
                onTap: () {
                  Navigator.pop(context);
                  addItemToCart(prod, 1, CartUnitType.retail);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void addItemToCart(Product prod, int qty, CartUnitType unitType) {
    setState(() {
      int requiredStock = 0;
      if (unitType == CartUnitType.quarter) {
        requiredStock = qty * (prod.retailConversion ~/ 4);
      } else if (unitType == CartUnitType.half) {
        requiredStock = qty * (prod.retailConversion ~/ 2);
      } else if (unitType == CartUnitType.retail) {
        requiredStock = qty;
      } else {
        requiredStock = qty * prod.retailConversion;
      }

      int existingIndex = cart.indexWhere((c) => c.product.id == prod.id && c.unitType == unitType);
      
      if (existingIndex != -1) {
        int newQty = cart[existingIndex].quantity + qty;
        int totalRequired = 0;
        if (unitType == CartUnitType.quarter) {
          totalRequired = newQty * (prod.retailConversion ~/ 4);
        } else if (unitType == CartUnitType.half) {
          totalRequired = newQty * (prod.retailConversion ~/ 2);
        } else if (unitType == CartUnitType.retail) {
          totalRequired = newQty;
        } else {
          totalRequired = newQty * prod.retailConversion;
        }

        if (totalRequired <= prod.stock) {
          cart[existingIndex].quantity = newQty;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok tidak cukup!')));
        }
      } else {
        if (requiredStock <= prod.stock) {
          cart.add(CartItem(product: prod, quantity: qty, unitType: unitType));
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
                    
                    if (paymentType == 'QRIS') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                        child: Column(
                          children: [
                            const Text('Scan QRIS Warung Barokah (Tap untuk Zoom)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => Dialog(
                                    backgroundColor: Colors.black,
                                    child: InteractiveViewer(
                                      panEnabled: true,
                                      boundaryMargin: const EdgeInsets.all(20),
                                      minScale: 0.5,
                                      maxScale: 4,
                                      child: Image.asset(
                                        'assets/images/qris.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Image.asset(
                                'assets/images/qris.png',
                                width: 180,
                                height: 180,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Nominal: ${currencyFormatter.format(grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                      )
                    ],

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

                    String summary = cart.map((i) => "${i.product.name} (${i.quantity} ${i.unitLabel})").join(", ");
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

  // ================= 2. HALAMAN MANAJEMEN PRODUK =================
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
      if (productSortOption == 'Barang Sales') return matchesSearch && prod.isConsignment;
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
                      DropdownMenuItem(value: 'Barang Sales', child: Text('🤝 Barang Sales/Titipan')),
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
                          title: Row(
                            children: [
                              Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (prod.isConsignment) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(4)),
                                  child: Text('Sales: ${prod.salesName}', style: TextStyle(fontSize: 9, color: Colors.orange[900], fontWeight: FontWeight.bold)),
                                )
                              ]
                            ],
                          ),
                          subtitle: Text(
                              'Kategori: ${prod.category} | Jual: ${currencyFormatter.format(prod.price)}\nStok: ${prod.getFormattedStock()}${prod.hasHalfPrice ? ' | 1/2: ${currencyFormatter.format(prod.halfPrice)}' : ''}${prod.hasQuarterPrice ? ' | 1/4: ${currencyFormatter.format(prod.quarterPrice)}' : ''}'),
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
    TextEditingController halfPriceCtrl = TextEditingController(text: isEdit ? product.halfPrice.toInt().toString() : '');
    TextEditingController quarterPriceCtrl = TextEditingController(text: isEdit ? product.quarterPrice.toInt().toString() : '');
    TextEditingController stockCtrl = TextEditingController(text: isEdit ? product.stock.toString() : '');
    TextEditingController barcodeCtrl = TextEditingController(
      text: isEdit ? product.barcode : (initialBarcode ?? ''),
    );
    
    TextEditingController retailNameCtrl = TextEditingController(text: isEdit ? product.retailName : '');
    TextEditingController retailConvCtrl = TextEditingController(text: isEdit ? product.retailConversion.toString() : '');
    TextEditingController retailPriceCtrl = TextEditingController(text: isEdit ? product.retailPrice.toInt().toString() : '');
    
    bool isConsignment = isEdit ? product.isConsignment : false;
    TextEditingController salesNameCtrl = TextEditingController(text: isEdit ? product.salesName : '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Edit Produk' : 'Tambah Produk Baru'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Barang Titipan Sales (Konsinyasi)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    value: isConsignment,
                    onChanged: (val) => setDialogState(() => isConsignment = val),
                  ),
                  if (isConsignment) ...[
                    TextField(controller: salesNameCtrl, decoration: const InputDecoration(labelText: 'Nama Sales / Supplier *')),
                    const SizedBox(height: 6),
                  ],
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
                  TextField(controller: buyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Modal / Harga Beli (Rp)')),
                  TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual 1 Bungkus/Utuh (Rp)')),
                  TextField(controller: halfPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual 1/2 Bungkus (Rp)')),
                  TextField(controller: quarterPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual 1/4 Bungkus (Rp)')),
                  TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total Stok Awal (Satuan Terkecil/Pcs)')),
                  const Divider(height: 20),
                  const Text('--- PENGATURAN ECERAN ---', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
                  TextField(controller: retailNameCtrl, decoration: const InputDecoration(labelText: 'Nama Satuan Eceran (Cth: Batang)')),
                  TextField(controller: retailConvCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Isi per Bungkus Utuh (Cth: 12)')),
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
                      halfPrice: double.tryParse(halfPriceCtrl.text) ?? 0,
                      quarterPrice: double.tryParse(quarterPriceCtrl.text) ?? 0,
                      stock: int.tryParse(stockCtrl.text) ?? 0,
                      retailName: retailNameCtrl.text,
                      retailConversion: int.tryParse(retailConvCtrl.text) ?? 1,
                      retailPrice: double.tryParse(retailPriceCtrl.text) ?? 0,
                      barcode: barcodeCtrl.text,
                      isConsignment: isConsignment,
                      salesName: salesNameCtrl.text,
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
          );
        },
      ),
    );
  }

  // ================= 3. HALAMAN KULAKAN / BELANJA ULANG =================
  Widget buildRestockPage() {
    List<Product> lowStockProducts = products.where((p) => p.stock < 10 && !p.isConsignment).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Belanja Ulang / Kulakan Stok Mandiri'),
        backgroundColor: Colors.green[800],
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
              child: const Text(
                '💡 Fitur Kulakan: Pilih barang yang stoknya menipis/habis atau ingin dibelanjakan kembali saat modal terkumpul. Masukkan jumlah kulakan dan total uang belanja, stok otomatis bertambah dan tercatat sebagai pengeluaran.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Daftar Produk Stok Menipis / Habis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Expanded(
              child: lowStockProducts.isEmpty
                  ? const Center(child: Text('Semua stok produk mandiri masih aman.'))
                  : ListView.builder(
                      itemCount: lowStockProducts.length,
                      itemBuilder: (context, index) {
                        final prod = lowStockProducts[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Stok Saat Ini: ${prod.getFormattedStock()}\nEstimasi Modal Satuan: ${currencyFormatter.format(prod.buyPrice)}'),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              onPressed: () => showRestockDialog(prod),
                              icon: const Icon(Icons.add_shopping_cart, size: 16),
                              label: const Text('Kulakan'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: OutlinedButton.icon(
                  onPressed: () => showRestockDialog(null),
                  icon: const Icon(Icons.search),
                  label: const Text('Cari Produk Lain untuk Kulakan'),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void showRestockDialog(Product? selectedProd) {
    Product? chosenProduct = selectedProd;
    TextEditingController addStockCtrl = TextEditingController(text: '10');
    TextEditingController totalCostCtrl = TextEditingController();
    TextEditingController staffCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Form Belanja Ulang / Kulakan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chosenProduct == null) ...[
                    DropdownButtonFormField<Product>(
                      decoration: const InputDecoration(labelText: 'Pilih Produk *', border: OutlineInputBorder(), isDense: true),
                      items: products.where((p) => !p.isConsignment).map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (Stok: ${p.stock})'))).toList(),
                      onChanged: (val) => setDialogState(() {
                        chosenProduct = val;
                        if (chosenProduct != null) {
                          double estCost = chosenProduct!.buyPrice * 10;
                          totalCostCtrl.text = estCost.toInt().toString();
                        }
                      }),
                    ),
                  ] else ...[
                    Text('Produk: ${chosenProduct!.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Stok Sekarang: ${chosenProduct!.getFormattedStock()}'),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: staffCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Pengelola / Kasir *', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah Tambahan Stok (Satuan Terkecil/Pcs)', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: totalCostCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Total Uang Belanja / Modal Keluar (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                onPressed: () {
                  if (chosenProduct == null || staffCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih produk dan isi nama pengelola!')));
                    return;
                  }
                  int addStock = int.tryParse(addStockCtrl.text) ?? 0;
                  double totalCost = double.tryParse(totalCostCtrl.text) ?? 0;

                  if (addStock <= 0 || totalCost <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jumlah stok dan total biaya harus valid!')));
                    return;
                  }

                  setState(() {
                    chosenProduct!.stock += addStock;
                  });
                  saveProductToGoogleSheets(chosenProduct!);

                  TransactionRecord restockTrx = TransactionRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                    date: DateTime.now(),
                    items: [],
                    subtotal: totalCost,
                    discount: 0,
                    tax: 0,
                    total: totalCost,
                    payAmount: totalCost,
                    change: 0,
                    customNetProfit: -totalCost,
                    itemsSummary: "Kulakan/Belanja Ulang: ${chosenProduct!.name} (+ $addStock Pcs)",
                    staffName: staffCtrl.text,
                    paymentType: 'Kulakan / Restock',
                  );
                  saveTransactionToGoogleSheets(restockTrx);
                  transactions.add(restockTrx);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Stok ${chosenProduct!.name} berhasil ditambah sebanyak $addStock Pcs!')),
                  );
                },
                child: const Text('Simpan Kulakan'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ================= 4. HALAMAN KONSINYASI / SALES =================
  Widget buildConsignmentReportPage() {
    List<Product> consignmentProducts = products.where((p) => p.isConsignment).toList();

    return Scaffold(
      body: consignmentProducts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Belum ada barang titipan sales (konsinyasi).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              itemCount: consignmentProducts.length,
              itemBuilder: (context, index) {
                final prod = consignmentProducts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(6)),
                              child: Text('Sales: ${prod.salesName}', style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                        const Divider(height: 12),
                        Text('Sisa Stok di Toko: ${prod.getFormattedStock()}', style: const TextStyle(fontSize: 13)),
                        Text('Harga Setoran (Modal ke Sales): ${currencyFormatter.format(prod.buyPrice)} per utuh', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white),
                              onPressed: () => showSalesSettlementDialog(prod),
                              icon: const Icon(Icons.sync, size: 16),
                              label: const Text('Sales Datang / Retur Ganti Baru'),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void showSalesSettlementDialog(Product prod) {
    TextEditingController physicalStockCtrl = TextEditingController(text: prod.stock.toString());
    TextEditingController newStockCtrl = TextEditingController(text: '0');
    TextEditingController staffCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          int physicalStock = int.tryParse(physicalStockCtrl.text) ?? prod.stock;
          int soldStock = prod.stock - physicalStock;
          if (soldStock < 0) soldStock = 0;

          double buyPerSmallUnit = prod.buyPrice / (prod.retailConversion > 0 ? prod.retailConversion : 1);
          double totalPayToSales = soldStock * buyPerSmallUnit;

          int restockAmount = int.tryParse(newStockCtrl.text) ?? 0;

          return AlertDialog(
            title: Text('Kunjungan Sales: ${prod.salesName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Barang: ${prod.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Stok Tercatat di Sistem: ${prod.stock} Pcs'),
                  const Divider(height: 20),
                  TextField(controller: staffCtrl, decoration: const InputDecoration(labelText: 'Nama Kasir *', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: physicalStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sisa Fisik Barang Sekarang', border: OutlineInputBorder()),
                    onChanged: (val) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estimasi Terjual: $soldStock Pcs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        const SizedBox(height: 4),
                        Text('Uang Setoran ke Sales: ${currencyFormatter.format(totalPayToSales)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green[850])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Tambah Stok Baru dari Sales (Restock)', border: OutlineInputBorder()),
                    onChanged: (val) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                onPressed: () {
                  if (staffCtrl.text.isEmpty) return;

                  setState(() {
                    prod.stock = physicalStock + restockAmount;
                  });
                  saveProductToGoogleSheets(prod);

                  TransactionRecord salesTrx = TransactionRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                    date: DateTime.now(),
                    items: [],
                    subtotal: totalPayToSales,
                    discount: 0,
                    tax: 0,
                    total: totalPayToSales,
                    payAmount: totalPayToSales,
                    change: 0,
                    customNetProfit: 0,
                    itemsSummary: "Setoran Sales [${prod.salesName}] - ${prod.name} (Terjual: $soldStock)",
                    staffName: staffCtrl.text,
                    paymentType: 'Setoran Sales Titipan',
                  );
                  saveTransactionToGoogleSheets(salesTrx);
                  transactions.add(salesTrx);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setoran ke sales berhasil dicatat!')));
                },
                child: const Text('Selesaikan & Bayar Sales'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ================= 5. HALAMAN KASBON =================
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
    TextEditingController payCtrl = TextEditingController(text: totalDebt.toString());
    TextEditingController staffCtrl = TextEditingController();
    String paymentType = 'Tunai';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double payAmount = double.tryParse(payCtrl.text) ?? 0;

          return AlertDialog(
            title: Text('Pelunasan Utang - $custName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total Sisa Utang: ${currencyFormatter.format(totalDebt)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 12),
                  TextField(controller: staffCtrl, decoration: const InputDecoration(labelText: 'Nama Kasir Penerima *', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: paymentType,
                    decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Tunai', child: Text('💵 Tunai')),
                      DropdownMenuItem(value: 'QRIS', child: Text('📱 QRIS (Non-Tunai)')),
                    ],
                    onChanged: (val) => setDialogState(() {
                      paymentType = val!;
                      if (paymentType == 'QRIS') payCtrl.text = totalDebt.toString();
                    }),
                  ),
                  const SizedBox(height: 8),
                  if (paymentType == 'QRIS') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                      child: Column(
                        children: [
                          const Text('Scan QRIS Pelunasan Utang (Tap untuk Zoom)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.black,
                                  child: InteractiveViewer(
                                    panEnabled: true,
                                    boundaryMargin: const EdgeInsets.all(20),
                                    minScale: 0.5,
                                    maxScale: 4,
                                    child: Image.asset(
                                      'assets/images/qris.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: Image.asset(
                              'assets/images/qris.png',
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('Nominal: ${currencyFormatter.format(payAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (paymentType != 'QRIS') ...[
                    TextField(
                      controller: payCtrl, 
                      keyboardType: TextInputType.number, 
                      decoration: const InputDecoration(labelText: 'Jumlah Pembayaran (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()), 
                      onChanged: (val) => setDialogState(() {}),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () {
                  if (staffCtrl.text.isEmpty) return;
                  double finalPayAmount = paymentType == 'QRIS' ? totalDebt : (double.tryParse(payCtrl.text) ?? 0);
                  if (finalPayAmount <= 0) return;

                  double remainingPay = finalPayAmount;

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
                        d.settlementHistory += "${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}: Bayar via $paymentType ${currencyFormatter.format(finalPayAmount)} (${staffCtrl.text})\n";
                        saveDebtToGoogleSheets(d);
                      }
                    }
                  });

                  TransactionRecord settlementTrx = TransactionRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                    date: DateTime.now(),
                    items: [],
                    subtotal: finalPayAmount,
                    discount: 0,
                    tax: 0,
                    total: finalPayAmount,
                    payAmount: finalPayAmount,
                    change: 0,
                    customNetProfit: finalPayAmount,
                    itemsSummary: "Pelunasan Piutang ($paymentType): $custName",
                    staffName: staffCtrl.text,
                    paymentType: 'Pelunasan Kasbon ($paymentType)',
                  );
                  saveTransactionToGoogleSheets(settlementTrx);
                  transactions.add(settlementTrx);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran berhasil dicatat!')));
                },
                child: const Text('Simpan'),
              )
            ],
          );
        },
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
                            pw.Text('${item.product.name} (${item.quantity} ${item.unitLabel})', style: const pw.TextStyle(fontSize: 8)),
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

  // ================= 6. HALAMAN LAPORAN =================
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
                            Text('${item.product.name} (${item.quantity} ${item.unitLabel})', style: const TextStyle(fontSize: 12)),
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
          receiptText += "${item.product.name} (${item.quantity} ${item.unitLabel})\n  = ${currencyFormatter.format(item.totalPrice)}\n";
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
