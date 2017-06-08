#include <iostream>
#include <memory>
#include <functional>
#include <string>
#include <set>

typedef int node_type;

struct tree_type {
    std::shared_ptr<tree_type> left;
    std::shared_ptr<tree_type> right;
    node_type value;
    tree_type(const node_type &v) {
        left = nullptr;
        right = nullptr;
        value = v;
    }
};

typedef std::shared_ptr<tree_type> tree_ptr;

tree_ptr insert(tree_ptr current, node_type value)
{
    if (current == nullptr) {
        return std::make_shared<tree_type>(value);
    } 

    if (value < current->value) {
        current->left = insert(current->left, value);
    } else {
        current->right = insert(current->right, value);
    }
    return current;
}

void tree_in_order(tree_ptr current, std::function<void (node_type&)> func)
{
    if (current != nullptr) {
        func(current->value);
        tree_in_order(current->left, func);
        tree_in_order(current->right, func);
    }
}

std::string shape(tree_ptr current)
{
    std::string ret = "";
    if (current != nullptr) {
        if (current->left != nullptr) {
            ret += "L";
            ret += shape(current->left);
        }
        ret += ".";
        if (current->right != nullptr) {
            ret += "R";
            ret += shape(current->right);
        }
    }
    return ret;
}



void p(node_type &n)
{
    std::cout << n;
}

int main()
{

    
    int n;
    int k;

    std::cin >> n;
    std::cin >> k;

    int c = n;
    std::set<std::string> types;
    while (c--> 0) {
        tree_ptr t = nullptr;
        
        for(int i=0;i<k;i++) {
            int v;
            std::cin >> v;
            t = insert(t, v);
        }
        types.insert(shape(t));
    }

    
    std::cout << types.size() << std::endl;
    

    return 0;
}

