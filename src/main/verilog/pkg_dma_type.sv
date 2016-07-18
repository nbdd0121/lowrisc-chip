package pkg_dma_type;
    typedef enum 
        { DMA_IDLE,
          DMA_INIT_ATTR,
          DMA_DECIDE_LENGTH, 
          DMA_FIRST_ASSERT_REQ,
          DMA_ASSERT_REQ,
          DMA_WAIT_ACK} 
        Dma_State;
endpackage