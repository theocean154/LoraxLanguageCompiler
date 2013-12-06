/*
 * Authors:
 * Chris D'Angelo & Kira Whitehouse
 */

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#define false 0
#define true !false

typedef enum {
  _BOOL_,
  _INT_,
  _FLOAT_,
  _CHAR_
} Atom;

typedef int bool;

typedef union Root {
        char char_root;
        int int_root;
        bool bool_root;
        float float_root;
} Root;


typedef struct tree{
      int degree;
      Atom datatype;
      
      Root root;

      /* array of children, which are themselves tree pointers */
      struct tree **children;

      bool leaf;
} tree;

int lrx_print_bool(bool b) {
  if (b) {
    fprintf(stderr, "true");
  } else {
    fprintf(stderr, "false");
  }
  return 0;
}

// TODO: the following functions are not implemented
int lrx_print_tree(struct tree *t) {
  //Occurs when tree is imbalanced (one child is instantiated and not the others)
  if(t == NULL){
    fprintf(stderr, "null");
    return 0;
  }

  switch (t->datatype){
    case _INT_:
      fprintf(stderr, "%d", t->root.int_root);
      break;

    case _FLOAT_:
      fprintf(stderr, "%f", t->root.float_root); 
      break;

    case _CHAR_:
      fprintf(stderr, "%c", t->root.char_root); 
      break;

    case _BOOL_:
      lrx_print_bool(t->root.float_root);
      break;

  }
  
  if(!t->leaf){
    int i;
    fprintf(stderr, "[");
    for(i = 0; i < t->degree; ++i){
      lrx_print_tree(t->children[i]);
      if(i != t->degree - 1){
        fprintf(stderr, ",");
      }
    }
    fprintf(stderr, "]");
  }

  return 0;

}

void lrx_destroy_tree(struct tree *t)
{
    if(t == NULL){
      fprintf(stderr, "t is null?!?!");
      return;
    }

    if(t->leaf){
      free(t->children);
      free(t);
      return;
    }

    int i;
    for(i = 0; i < t->degree; ++i)
        lrx_destroy_tree(t->children[i]);
    
    free(t->children);
    free(t);
}

struct tree *lrx_declare_tree(Atom type, int deg){

    assert(deg > 0);

    struct tree *t = (struct tree *)malloc(sizeof(struct tree));
    assert(t != NULL);
    t->degree = deg;
    t->datatype = type;

    switch(type){
      case _BOOL_:
          t->root.bool_root = false;
          break;

        case _INT_:
          t->root.int_root = 0;
          break;

        case _FLOAT_:
          t->root.float_root = 0.0;
          break;
  
        case _CHAR_:
          t->root.char_root = '\0';
          break;
    }


    t->leaf = true;
    t->children = (struct tree **)malloc(sizeof(struct tree *) * t->degree);
    return t;
}

struct tree *lrx_define_tree(struct tree *t, void *root_data, struct tree **children)
{

    /* set root data */
    switch(t->datatype){
        case _BOOL_:
          t->root.bool_root = *((bool *)root_data);
          break;

        case _INT_:
          t->root.int_root = *((int *)root_data);
          break;

        case _FLOAT_:
          t->root.float_root = *((float *)root_data);
          break;
  
        case _CHAR_:
          t->root.char_root = *((char *)root_data);
          break;
    }

    if(children == NULL)
      return t;

    /* set pointers to children */
    int num_children = t->degree;
    int i;
    for(i = 0; i < num_children; ++i)
        t->children[i] = children[i]; 
    t->leaf = false;  

    return t;
}

/* data = t@; */
bool lrx_access_data_at_bool (struct tree *t)
{
    assert(t != NULL);
    return t->root.bool_root;
}
int lrx_access_data_at_int (struct tree *t)
{
    assert(t != NULL);
    return t->root.int_root;
}
float lrx_access_data_at_float (struct tree *t)
{
    assert(t != NULL);
    return t->root.float_root;
}
char lrx_access_data_at_char (struct tree *t)
{
    assert(t != NULL);
    return  t->root.char_root;
}

/* t@ = data */
bool lrx_assign_data_at_bool (struct tree *t, const bool data)
{
    assert(t != NULL);
    t->root.bool_root = data;
}
int lrx_assign_data_at_int (struct tree *t, const int data)
{
    assert(t != NULL);
    t->root.int_root = data;
}
float lrx_assign_data_at_float (struct tree *t, const float data)
{
    assert(t != NULL);
    t->root.float_root = data;
}
char lrx_assign_data_at_char (struct tree *t, const char data)
{
    assert(t != NULL);
    t->root.char_root = data;
}

/* t1 = t2%0 */
struct tree *lrx_access_child (struct tree *t, const int child)
{
  assert(child < t->degree);
  struct tree **children = t->children;
  return *(children + child);
}

/* t1 = t2%0 */
struct tree *lrx_assign_tree (struct tree *t1, struct tree *t2)
{

    assert(t1->degree == t2->degree);
  
    t1->root = t2->root;
    t1->leaf = t2->leaf;
    t1->children = t2->children;

    return t1;
}

struct tree *lrx_assign_child(struct tree *t1, int child, struct tree *t2)
{
  /*here t1 is a leaf node*/
  assert(child < t1->degree);

  struct tree *access = lrx_access_child(t1, child);
  if(access && t2) {
    return lrx_assign_tree(access, t2);
  }
  else {
    t1->children[child] = t2;
    t1->leaf = false;
    return t1;
  }
}











