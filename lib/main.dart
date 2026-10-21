import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

void main() {
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

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.buyPrice,
    required this.price,
    required this.stock,
  });
}

class CartItem {
  Product product;
  int quantity;

  CartItem({required this.product, required this.quantity});

  double get totalPrice => product.price * quantity;
  double get totalBuyPrice => product.buyPrice * quantity;
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
  });

  double get totalCapital => items.fold(0, (sum, item) => sum + item.totalBuyPrice);
  double get netProfit => (subtotal - discount) - totalCapital;
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  List<Product> products = [
    Product(id: '1', name: 'Beras C4 (1 kg)', category: 'Sembako', buyPrice: 12500, price: 14000, stock: 50),
    Product(id: '2', name: 'Minyak Goreng 1L', category: 'Sembako', buyPrice: 14500, price: 16500, stock: 3),
    Product(id: '3', name: 'Gula Pasir 1 kg', category: 'Sembako', buyPrice: 15500, price: 17500, stock: 0),
    Product(id: '4', name: 'Telur Ayam 1 kg', category: 'Sembako', buyPrice: 25000, price: 28000, stock: 15),
    Product(id: '5', name: 'Mie Goreng', category: 'Makanan Ringan', buyPrice: 2500, price: 3000, stock: 100),
  ];

  List<CartItem> cart = [];
  List<TransactionRecord> transactions = [];

  TextEditingController searchKasirController = TextEditingController();
  String searchKasirQuery = '';
  String selectedCategory = 'Semua';

  TextEditingController searchMasterController = TextEditingController();
  String searchMasterQuery = '';
  String productSortOption = 'Default';

  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    fetchProductsFromGoogleSheets();
  }

  Future<void> fetchProductsFromGoogleSheets() async {
    final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec');
    try {
      final response = await http.get(url);
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
                    ))
                .toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat dari Google Sheets: $e");
    }
  }

  Future<void> addProductToGoogleSheets(Product newProduct) async {
    final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec');
    try {
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "id": newProduct.id,
          "name": newProduct.name,
          "category": newProduct.category,
          "buyPrice": newProduct.buyPrice,
          "price": newProduct.price,
          "stock": newProduct.stock,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan ke Google Sheets: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      buildKasirPage(),
      buildProductManagementPage(),
      buildHistoryPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Warung Barokah',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Kiarajangkung',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Produk',
            onPressed: () {
              fetchProductsFromGoogleSheets();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memperbarui data produk...')),
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
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart), label: 'Kasir'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2), label: 'Produk/Stok'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
        ],
      ),
    );
  }

  List<String> getCategories() {
    Set<String> categories = {'Semua'};
    for (var p in products) {
      if (p.category.isNotEmpty) {
        categories.add(p.category);
      }
    }
    return categories.toList();
  }

  // ================= 1. HALAMAN KASIR =================
  Widget buildKasirPage() {
    double subtotal = cart.fold(0, (sum, item) => sum + item.totalPrice);
    List<String> categories = getCategories();

    List<Product> filteredProducts = products.where((prod) {
      bool matchesSearch = prod.name.toLowerCase().contains(searchKasirQuery.toLowerCase());
      bool matchesCategory = selectedCategory == 'Semua' || prod.category == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: searchKasirController,
            decoration: InputDecoration(
              hintText: 'Cari produk...',
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            onChanged: (value) {
              setState(() {
                searchKasirQuery = value;
              });
            },
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
                  onSelected: (bool selected) {
                    setState(() {
                      selectedCategory = cat;
                    });
                  },
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
                      title: Text(prod.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${prod.category} | Jual: ${currencyFormatter.format(prod.price)} \vert{} Stok:${prod.stock}'),
                      trailing: ElevatedButton(
                        onPressed: prod.stock > 0
                            ? () {
                                setState(() {
                                  int existingIndex = cart.indexWhere(
                                      (c) => c.product.id == prod.id);
                                  if (existingIndex != -1) {
                                    if (cart[existingIndex].quantity <
                                        prod.stock) {
                                      cart[existingIndex].quantity++;
                                    }
                                  } else {
                                    cart.add(
                                        CartItem(product: prod, quantity: 1));
                                  }
                                });
                              }
                            : null,
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
                        title: Text(item
